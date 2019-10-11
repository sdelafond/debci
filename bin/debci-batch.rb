#!/usr/bin/ruby
# coding: utf-8

require 'date'
require 'fileutils'
require 'optparse'

require 'debci'
require 'debci/job'

# defaults for global variables
$dry_run = false
$arch = Debci.config.arch
$suite = Debci.config.suite
$force = false

# defaults for local variables
online = nil

# FIXME: the following four should come from Debci::Config
debci_lock_dir = "/var/lock"
$debci_quiet = false
debci_user = "debci"
debci_group = "debci"

debci_data_basedir = Debci.config.data_basedir
$debci_packages_dir = Debci.config.packages_dir
offline_marker = File.join(debci_data_basedir, "offline")

# parse command line
optparse = OptionParser.new do |opts|
  opts.banner = 'Usage: debci batch [OPTIONS]'
  opts.separator 'Options:'

  opts.on('-f', '--force') do
    $force = true
  end

  opts.on('--online') do
    online = true
  end

  opts.on('--offline') do
    online = false
  end

  opts.on('--dry-run') do
    $dry_run = true
  end

  opts.on('-s', '--suite SUITE', 'sets the suite to test') do |s|
    $suite = s
  end

  opts.on('-a', '--arch ARCH', 'sets architecture to test') do |a|
    $arch = a
  end

  opts.on('-b', '--backend BACKEND', 'sets the test backend') do |b|
    Debci.config.backend = b
  end
end
optparse.parse!

$debci_chdist_lock = File.join(debci_lock_dir, "debci-chdist-#{$suite}-#{$arch}.lock")
debci_batch_lock = File.join(debci_lock_dir, "debci-batch-#{$suite}-#{$arch}.lock")

def now
  return DateTime.now.strftime("%a %d %b %Y %l:%m:%S %p %Z")
end

# FIXME: move to some common library
def report_status(pkg, status, duration = nil)
  if $debci_quiet then
    return
  end

  if STDOUT.isatty then
    color = case status
            when "skip", "neutral"
              8
            when "pass"
              2
            when "fail"
              1
            when "tmpfail", "requested"
              3
            else
              5
            end
    Debci.log "#{pkg} #{$suite}/#{$arch} \033[38;5;#{color}m#{status}\033[m #{duration}"
  else
    Debci.log "#{pkg} #{$suite}/#{$arch} #{status} #{duration}"
  end
end

# FIXME: move to some common library
def status_dir_for_package(pkg)
  pkg_dir = pkg.gsub(/^?=lib/, "lib/") # libfoo -> lib/libfoo
  return File.join($debci_packages_dir, pkg_dir)
end

# FIXME: move to some common library
def run_system_command(cmd)
  output = `#{cmd}`
  rc = $?.exitstatus
  if rc != 0 then
    Debci.log("Error while running '#{cmd}':")
    Debci.log(output)
    exit(rc)
  end
  return output
end

# FIXME: move to some common library
def run_with_exclusive_lock(lock_file, cmd, system_cmd = true)
  File.open(lock_file, File::CREAT) do |f|
    f.flock(File::LOCK_EX)
    if system_cmd then
      run_system_command(cmd)
    else
      send(cmd)
    end
  end
end  

# FIXME: move to some common library
def run_with_lock_or_exit(lock_file, cmd, system_cmd = true)
  File.open(lock_file, File::CREAT) do |f|
    # false when already locked, 0 otherwise
    ret = f.flock(File::LOCK_EX | File::LOCK_NB)

    if ret == 0 then
      if system_cmd then
        run_system_command(cmd)
      else
        send(cmd)
      end
    end
  end
end

def add_to_reason_file(pkg, msg)
  status_dir = status_dir_for_package(pkg)
  reason = File.join(status_dir, "reason.txt")

  Debci.log(msg)
  if not $dry_run then
    File.open(reason, 'a') do |fd|
      fd.write(msg)
    end
  end
end

def run()
  Debci.log "I: debci-batch started #{now()}"

  Debci.log "I: building/updating chdist for #{$suite}"
  cmd = "debci setup-chdist --suite #{$suite} --arch #{$arch}"
  run_with_exclusive_lock($debci_chdist_lock, cmd)

  Debci.log "I: start processing of all packages"

  process_all_packages()

  Debci.log "I: debci-batch finished #{now()}"
end

def all_packages_with_fastest_first()
  cmd = "debci status --suite #{$suite} --arch #{$arch} --field duration_seconds --all"
  output = run_system_command(cmd)
  lines = output.split(/\n/)

  packages = lines.map do |e| # "foo    nnn" -> ("foo", nnn:int)
    p, d = e.split()
    [p, d.to_i]
  end
  
  packages.sort! do |a,b|
    a[1] <=> b[1] # compare on 2nd field
  end

  return packages.map { |e| e[0] }
end

def process_all_packages()
  start = now()

  # TODO: we need something more flexible than $debci_backend here -- look at
  # tests' isolation restrictions
  Debci::Job.get_queue($arch)

  # determine packages which need to be tested and request tests
  all_packages_with_fastest_first().each do |pkg|
    Debci.log("Looking at #{pkg}")
    if (! already_enqueued(pkg)) && needs_processing(pkg, $force) then
      Debci.log("∙ --> enqueuing")
      job = Debci::Job.new(
        package: pkg,
        arch: $arch,
        suite: $suite,
        status: nil
      )
      if not $dry_run then
        job.save!
        record_enqueued(pkg)
        # FIXME: set priority
        job.enqueue(priority)
      end
    else
      Debci.log("∙ --> skipping")
      report_status(pkg, "skip")
    end
  end
end

def needs_processing(pkg, force)
  tmp_dir = File.join($base_tmp_dir, $suite, $arch, pkg)
  FileUtils.mkdir_p(tmp_dir)

  status_dir = status_dir_for_package(pkg)
  FileUtils.mkdir_p(status_dir)

  cmd = "debci status #{pkg}"
  last_status = run_system_command(cmd)

  cmd = "debci list-dependencies --suite #{$suite} --arch #{$arch} #{pkg}"
  dependencies = run_system_command(cmd)

  dependencies_file = File.join(tmp_dir, "#{pkg}-deps.txt")
  File.open(dependencies_file, 'w') do |fd|
    fd.write(dependencies)
  end

  run = false

  if last_status == 'tmpfail' then
    run = true
    add_to_reason_file(pkg, "∙ Retrying run since last attempt failed")
  end

  if force then
    run = true
    add_to_reason_file(pkg, "∙ Forced test run for #{pkg}")
  end

  latest = File.join(status_dir, "latest.json")
  seconds_in_one_month = Time.now - 30 * 24 * 60 * 60

  if File.exists?(latest) && (File.mtime(latest) > seconds_in_one_month) then
    run = true
    add_to_reason_file(pkg, "∙ Forcing test run after 1 month without one")
  end

  old_dependencies_file = File.join(status_dir, "dependencies.txt")

  if File.file?(old_dependencies_file) then
    diff = `diff -u --label last-run/dependencies.txt #{old_dependencies_file} --label current-run/dependencies.txt #{dependencies_file}`
    rc = $?.exitstatus

    if rc == 0 then
      # no need to run tests
    else
      run = true
      add_to_reason_file(pkg, "∙ There were changes in the dependency chain since last test run")
      add_to_reason_file(pkg, diff)
    end
  else
    run = true
    add_to_reason_file(pkg, "∙ First test run for #{pkg}")
  end

  if run and not $dry_run then
    FileUtils.copy(dependencies_file, old_dependencies_file)
  end

  Debci.log("∙ needs_processing returns #{run}")
  return run
end

def already_enqueued(pkg)
  status_dir = status_dir_for_package(pkg)
  # XXX if you change the line below also change in record_enqueued()
  queue_marker = File.join(status_dir, "queue.txt")
  last_result = File.join(status_dir, "latest.json")

  if File.exists?(queue_marker) then
    if File.exists?(last_result) then
      # already enqueued if last result is older than last request
      delta = File.mtime(last_result) - File.mtime(queue_marker)
      Debci.log("∙ timestamp difference between last result and last request #{delta}")
      return delta > 0
    else
      # already enqueued, just not finished yet
      Debci.log("∙ already enqueued, but not finished yet")
      return true
    end
  else
    # never enqueued before
      Debci.log("∙ never enqueued before")
    return false
  end
end

def record_enqueued(pkg)
  status_dir = status_dir_for_package(pkg)
  # XXX if you change the line below also change in already_enqueued()
  queue_marker = File.join(status_dir, "queue.txt")

  FileUtils.mkdir_p(status_dir)

  # FIXME: log to file
  File.open(queue_marker, 'w') { |fd| fd.write("Enqueued at #{now()}") }
end

## main

if not online.nil? then
  if online then
    FileUtils.rm(offline_marker) if File.exists?(offline_marker)
  else
    FileUtils.touch(offline_marker)
  end
  exit()
end

exit() if File.exists?(offline_marker)

Dir.mktmpdir do |tmpdir|
  $base_tmp_dir = tmpdir
  run_with_lock_or_exit(debci_batch_lock, "run", false)
end
