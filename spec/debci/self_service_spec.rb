require 'spec_mock_server'
require 'debci'
require 'debci/self_service'
require 'rack/test'
require 'json'

describe Debci::SelfService do
  include Rack::Test::Methods

  class SelfService < Debci::SelfService
    set :raise_errors, true
    set :show_exceptions, false
  end

  def app
    mock_server('/user', SelfService)
  end

  def create_json_file(obj)
    temp_test_file = Tempfile.new
    temp_test_file.write(JSON.dump(obj))
    temp_test_file.rewind
    temp_test_file
  end

  let(:suite) { Debci.config.suite }
  let(:arch) { Debci.config.arch }

  context 'authentication' do
    it 'redirects to self service section to authenticated users' do
      get '/user', {}, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(302)
      expect(last_response.content_type).to match('text/html')
    end
    it 'displays self service section to authenticated users' do
      get '/user/foo@bar.com', {}, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to match('text/html')
    end
    it 'directs to 403 to unauthenticated users' do
      get '/user'
      expect(last_response.status).to eq(403)
      expect(last_response.content_type).to match('text/html')
    end
  end

  context 'request test form' do
    it 'exports a json file successfully from test form' do
      post '/user/foo@bar.com/test/submit', { pin_packages: '', trigger: 'test_trigger', package: 'test-package', suite: suite, arch: [arch], export: true }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to match('application/json')
    end

    it 'should return error when exporting a json file from incomplete test form' do
      post '/user/foo@bar.com/test/submit', { pin_packages: '', trigger: '', package: '', suite: suite, arch: [arch], export: true }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(400)
    end

    it 'submits a task succesfully from the form' do
      post '/user/foo@bar.com/test/submit', { pin_packages: '', trigger: 'test_trigger', package: 'test-package', suite: suite, arch: [arch] }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(201)
      job = Debci::Job.last
      expect(job.package).to eq('test-package')
      expect(job.trigger).to eq('test_trigger')
      expect(job.arch).to eq(arch)
      expect(job.suite).to eq(suite)
      expect(job.pin_packages).to eq([])
    end

    it 'should return error when submitting form with empty package field' do
      job_count = Debci::Job.count
      post '/user/foo@bar.com/test/submit', { pin_packages: '', trigger: 'test_trigger', package: '', suite: suite, arch: [arch] }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(Debci::Job.count).to eq(job_count)
      expect(last_response.status).to eq(400)
    end

    it 'should return error when submitting form with empty suite field' do
      job_count = Debci::Job.count
      post '/user/foo@bar.com/test/submit', { pin_packages: '', trigger: 'test_trigger', package: 'test-package', suite: '', arch: [arch] }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(Debci::Job.count).to eq(job_count)
      expect(last_response.status).to eq(400)
    end

    it 'should return error when submitting form with empty arch field' do
      job_count = Debci::Job.count
      post '/user/foo@bar.com/test/submit', { pin_packages: '', trigger: '', package: 'test-package', suite: suite, arch: [] }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(Debci::Job.count).to eq(job_count)
      expect(last_response.status).to eq(400)
    end
  end

  context 'upload json file' do
    it 'submits a task succesfully on a valid json file upload' do
      test_json = [
        {
          "suite": suite,
          "arch": [arch],
          "tests": [
            {
              "trigger": "testing",
              "package": "autodep8",
              "pin-packages": [["src:bar", "unstable"], ["foo", "src:bar", "stable"]]
            }
          ]
        }
      ]
      test_file = create_json_file(test_json)
      post '/user/foo@bar.com/test/upload', { tests: Rack::Test::UploadedFile.new(test_file) }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(201)
      job = Debci::Job.last
      expect(job.package).to eq('autodep8')
      expect(job.suite).to eq(suite)
    end

    it 'should return error with no file selected for uplaod' do
      job_count = Debci::Job.count
      post '/user/foo@bar.com/test/upload', {}, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(400)
      expect(Debci::Job.count).to eq(job_count)
    end

    it 'should return error with an invalid suite' do
      test_json = [
        {
          # invalid suite
          "suite": "xyz",
          "arch": ["arm64", "amd64"],
          "tests": [
            {
              "trigger": "testing",
              "package": "autodep8",
              "pin-packages": [["src:bar", "unstable"], ["foo", "src:bar", "stable"]]
            }
          ]
        }
      ]
      test_file = create_json_file(test_json)
      job_count = Debci::Job.count
      post '/user/foo@bar.com/test/upload', { tests: Rack::Test::UploadedFile.new(test_file) }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(400)
      expect(Debci::Job.count).to eq(job_count)
    end

    it 'should return error with an invalid arch' do
      test_json = [
        {
          "suite": "unstable",
          # invalid arch
          "arch": ["xyz", "amd64"],
          "tests": [
            {
              "trigger": "testing",
              "package": "autodep8",
              "pin-packages": [["src:bar", "unstable"], ["foo", "src:bar", "stable"]]
            }
          ]
        }
      ]
      test_file = create_json_file(test_json)
      job_count = Debci::Job.count
      post '/user/foo@bar.com/test/upload', { tests: Rack::Test::UploadedFile.new(test_file) }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(400)
      expect(Debci::Job.count).to eq(job_count)
    end
  end

  context 'history' do
    before do
      history_jobs = [
        {
          suite: "unstable",
          arch: "amd64",
          trigger: "mypackage/0.0.1",
          package: "mypackage",
          pin_packages: ["src:mypackage", "unstable"],
          requestor: "foo@bar.com"
        },
        {
          suite: "unstable",
          arch: "amd64",
          trigger: "testpackage/0.0.1",
          package: "testpackage",
          pin_packages: ["src:mypackage", "unstable"],
          requestor: "foo@bar.com"
        },
        {
          suite: "unstable",
          arch: "arm64",
          trigger: "testpackage/0.0.2",
          package: "testpackage",
          pin_packages: ["src:mypackage", "unstable"],
          requestor: "foo@bar.com"
        }
      ]

      history_jobs.each do |job|
        Debci::Job.create(job)
      end
    end

    it 'displays correct results with package filter' do
      get '/user/foo@bar.com/jobs', { package: 'package', trigger: '' }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to match('mypackage/0.0.1')
      expect(last_response.body).to match('testpackage/0.0.1')
      expect(last_response.body).to match('testpackage/0.0.2')
    end

    it 'displays correct results with trigger and arch filters' do
      get '/user/foo@bar.com/jobs', { package: '', trigger: 'mypackage/0.0.1', arch: [arch] }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to match('mypackage/0.0.1')
    end

    it 'displays correct results with arch filter' do
      get '/user/foo@bar.com/jobs', { package: '', trigger: '', arch: [arch] }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to match('mypackage/0.0.1')
      expect(last_response.body).to match('testpackage/0.0.1')
      expect(last_response.body).to_not match('testpackage/0.0.2')
    end

    it 'displays correct results with all filters' do
      get '/user/foo@bar.com/jobs', { package: 'package', trigger: 'package/0.0.1', arch: [arch], suite: [suite] }, 'SSL_CLIENT_S_DN_CN' => 'foo@bar.com'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to match('mypackage/0.0.1')
      expect(last_response.body).to match('testpackage/0.0.1')
      expect(last_response.body).to_not match('testpackage/0.0.2')
    end
  end
end