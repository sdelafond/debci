require 'sinatra'
require 'json'
require 'kaminari/core'
require 'kaminari/activerecord'

require 'debci/app'
require 'debci/test_handler'

module Debci
  class SelfService < Debci::App
    include Debci::TestHandler

    set :views, File.dirname(__FILE__) + '/html'

    configure do
      set :suites, Debci.config.suite_list
      set :archs, Debci.config.arch_list
    end

    get '/' do
      halt(403, "Unauthenticated!\n") unless @user
      redirect("/user/#{@user}")
    end

    get '/:user' do
      redirect("/user/#{params[:user]}/jobs") unless @user == params[:user]
      erb :self_service
    end

    get '/:user/test' do
      redirect("/user/#{params[:user]}/jobs") unless @user == params[:user]
      erb :self_service_test
    end

    post '/:user/test/submit' do
      trigger = params[:trigger] || ''
      package = params[:package] || ''
      suite = params[:suite] || ''
      archs = (params[:arch] || []).reject(&:empty?)
      pin_packages = (params[:pin_packages] || '').split(/\n+|\r+/).reject(&:empty?)

      # assemble test request
      test_obj = {
        'trigger' => trigger,
        'package' => package
      }
      test_obj['pin-packages'] = []
      pin_packages.each do |pin_package|
        pin_package = pin_package.split(/,\s*/)
        test_obj['pin-packages'].push(pin_package)
      end
      test_request = {
        'archs' => archs,
        'suite' => suite,
        'tests' => [test_obj]
      }

      # validate inputs
      begin
        validate_form_submission(package, suite, archs)
        archs.each do |arch|
          request_tests(test_request['tests'], suite, arch, @user)
        end
      rescue StandardError => error
        @error_msg = error
        halt(400, erb(:self_service_test))
      end

      # user clicks on export to json
      if params[:export]
        content_type :json
        [200, [test_request].to_json]
      # user submits test
      else
        @success = true
        [201, erb(:self_service_test)]
      end
    end

    def validate_form_submission(package, suite, archs)
      raise 'Please enter a valid package name' unless valid_package_name?(package)
      raise 'Please select a suite' if suite == ''
      raise 'Please select an architecture' if archs.empty?
    end

    post '/:user/test/upload' do
      begin
        raise "Please select a JSON file to upload" if params[:tests].nil?
        test_requests = JSON.parse(File.read(params[:tests][:tempfile]))
        errors = validate_batch_test(test_requests)
        raise errors.join("<br>") unless errors.empty?
        request_batch_tests(test_requests, @user)
      rescue JSON::ParserError => error
        halt(400, "Invalid JSON: #{error}")
      rescue StandardError => error
        @error_msg = error
        halt(400, erb(:self_service_test))
      else
        @success = true
        [201, erb(:self_service_test)]
      end
    end

    get '/:user/jobs/?' do
      user = params[:user]
      arch_filter = params[:arch]
      suite_filter = params[:suite]
      package_filter = params[:package] || ''
      trigger_filter = params[:trigger] || ''
      query = {
        requestor: user
      }
      query[:arch] = arch_filter if arch_filter
      query[:suite] = suite_filter if suite_filter
      @history = Debci::Job.where(query)

      unless package_filter.empty?
        @history = @history.where('package LIKE :query', query: "%#{package_filter}%") unless package_filter.nil?
      end

      unless trigger_filter.empty?
        @history = @history.where('trigger LIKE :query', query: "%#{trigger_filter}%") unless trigger_filter.nil?
      end

      # pagination
      @current_page = params[:page] || 1
      @history = @history.page(@current_page).per(10)
      @total_pages = @history.total_pages

      # generate query params
      query_params = {}
      params.each do |key, val|
        case val
        when Array then query_params["#{key}[]"] = val
        else
          query_params[key] = val
        end
      end
      erb :self_service_history, locals: { query_params: query_params, arch_filter: arch_filter, suite_filter: suite_filter, package_filter: package_filter, trigger_filter: trigger_filter }
    end
  end
end