require 'spec_helper'

require 'debci/job'

describe Debci::Job do

  it 'sets created_at' do
    job = Debci::Job.create
    expect(job.created_at).to_not be_nil
  end
  it 'sets updated_at' do
    job = Debci::Job.create
    job.save!
    expect(job.updated_at).to_not be_nil
  end

  it 'lists pending jobs' do
    job = Debci::Job.create
    expect(Debci::Job.pending).to include(job)
  end

  it 'sorts pending jobs with older first' do
    job1 = Debci::Job.create
    yesterday = Time.now - 1.day
    expect(Time).to receive(:now).and_return(yesterday)
    job0 = Debci::Job.create

    expect(Debci::Job.pending).to eq([job0, job1])
  end


  it 'escapes trigger' do
    job = Debci::Job.new(trigger: 'foo bar')
    expect(job.get_enqueue_parameters).to_not include('trigger:foo bar')
    expect(job.get_enqueue_parameters).to include('trigger:foo+bar')
  end

  [
    'áéíóú',
    '`cat /etc/passwd`',
    '$(cat /etc/passwd)',
    "a\nb",
  ].each do |invalid|
    it('escapes \"%s" in trigger' % invalid) do
      job = Debci::Job.new(trigger: invalid)
      expect(job.get_enqueue_parameters).to_not include(invalid)
    end
  end

  let(:suite) { 'unstable' }
  let(:arch) { 'amd64'}

  it 'imports status file' do
    job = Debci::Job.create(suite: suite, arch: arch)
    file = Tempfile.new('foo')
    file.write(
      {
        'run_id': job.run_id,
        'status': 'pass',
        'version': '1.0-1',
        'duration_seconds': 11,
        'date': '2018-09-09 20:40:00',
        'last_pass_date': '2018-01-09 20:40:00',
        'last_pass_version': '0.9-1',
        'message': 'bla bla bla',
        'previous_status': 'fail'
      }.to_json
    )
    file.close

    imported = Debci::Job.import(file.path, suite, arch)
    expect(imported).to eq(job)

    job.reload
    expect(job.status).to eq('pass')
    expect(job.version).to eq('1.0-1')
    expect(job.duration_seconds).to eq(11)
    expect(job.date).to eq(Time.utc(2018, 9, 9, 20, 40, 0))
    expect(job.last_pass_date).to eq(Time.utc(2018, 1, 9, 20, 40, 0))
    expect(job.last_pass_version).to eq('0.9-1')
    expect(job.message).to eq('bla bla bla')
    expect(job.previous_status).to eq('fail')
  end

end
