## SONATA - Gatekeeper
##
## Copyright (c) 2015 SONATA-NFV [, ANY ADDITIONAL AFFILIATION]
## ALL RIGHTS RESERVED.
## 
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
## 
##     http://www.apache.org/licenses/LICENSE-2.0
## 
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
## 
## Neither the name of the SONATA-NFV [, ANY ADDITIONAL AFFILIATION]
## nor the names of its contributors may be used to endorse or promote 
## products derived from this software without specific prior written 
## permission.
## 
## This work has been performed in the framework of the SONATA project,
## funded by the European Commission under Grant number 671517 through 
## the Horizon 2020 and 5G-PPP programmes. The authors would like to 
## acknowledge the contributions of their colleagues of the SONATA 
## partner consortium (www.sonata-nfv.eu).
# encoding: utf-8
require 'json' 
require 'pp'
require 'yaml'
require 'bunny'

class GtkSrv < Sinatra::Base  
  
  # GETs a request, given an uuid
  get '/requests/:uuid/?' do
    logger.debug(MODULE) {" entered GET /requests/#{params[:uuid]}"}
    request = Request.find(params[:uuid])
    json_request = json(request, { root: false })
    halt 206, json_request if request
    json_error 404, "#{MODULE}: Request #{params[:uuid]} not found"    
  end
  
  
  # GET many requests
  get '/requests/?' do

    logger.info(MODULE) {" entered GET /requests#{query_string}"}
    logger.info(MODULE) {" params=#{params}"}
    
    # transform 'string' params Hash into keys
    keyed_params = keyed_hash(params)
    
    # get rid of :offset and :limit
    [:offset, :limit].each { |k| keyed_params.delete(k)}
    valid_fields = [:service_uuid, :status, :created_at, :updated_at]
    logger.info(MODULE) {" keyed_params.keys - valid_fields = #{keyed_params.keys - valid_fields}"}
    json_error 400, "GtkSrv: wrong parameters #{params}" unless keyed_params.keys - valid_fields == []
    
    requests = Request.where(keyed_params).limit(params['limit'].to_i).offset(params['offset'].to_i)
    json_requests = json(requests, { root: false })
    logger.info(MODULE) {" leaving GET /requests?#{query_string} with "+json_requests}
    if json_requests
      headers 'Record-Count'=>requests.size.to_s, 'Content-Type'=>'application/json'
      halt 200, json_requests
    end
    json_error 404, 'GtkSrv: No requests were found'
  end

  # POSTs an instantiation request, given a service_uuid
  post '/requests/?' do
    log_msg = MODULE + '::POST /requests'
    original_body = request.body.read
    logger.debug(log_msg) {"entered with original_body=#{original_body}"}
    params = JSON.parse(original_body, quirks_mode: true)
    logger.debug(log_msg) {"with params=#{params}"}
    
    # we're not storing egresses or ingresses
    egresses = params.delete['egresses']
    ingresses = params.delete['ingresses']
    
    begin
      start_request={}

      si_request = Request.create(params)
      logger.debug(log_msg) { "with service_uuid=#{params['service_uuid']}: #{si_request.inspect}"}
      service = NService.new(settings.services_catalogue, logger).find_by_uuid(params['service_uuid'])
      logger.error(log_msg) {"network service not found"} unless service
      logger.debug(log_msg) { "service=#{service}"}

      nsd = service['nsd']
      nsd[:uuid] = service['uuid']
      start_request['NSD']= nsd
    
      nsd['network_functions'].each_with_index do |function, index|
        logger.debug(log_msg) { "function=['#{function['vnf_name']}', '#{function['vnf_vendor']}', '#{function['vnf_version']}']"}
        stored_function = VFunction.new(settings.functions_catalogue, logger).find_function(function['vnf_name'],function['vnf_vendor'],function['vnf_version'])
        logger.error(log_msg) {"network function not found"} unless stored_function
        logger.debug(log_msg) {"function#{index}=#{stored_function}"}
        vnfd = stored_function[:vnfd]
        vnfd[:uuid] = stored_function[:uuid]
        start_request["VNFD#{index}"]=vnfd 
        logger.debug(log_msg) {"start_request[\"VNFD#{index}\"]=#{vnfd}"}
      end
      start_request['egresses'] = egresses
      start_request['ingresses'] = ingresses
      stringified=start_request.deep_stringify_keys
      start_request_yml = YAML.dump(stringified)
      logger.debug(log_msg) {"#{params}: "+start_request_yml}

      smresponse = settings.mqserver.publish( start_request_yml.to_s, si_request['id'])
      json_request = json(si_request, { root: false })
      logger.info(MODULE) {' returning POST /requests with request='+json_request}
      halt 201, json_request
    rescue Exception => e
      logger.debug(e.message)
	    logger.debug(e.backtrace.inspect)
	    halt 500, 'Internal server error'+e.message
    end
  end

  # PUTs an update on an existing instantiation request, given its UUID
  put '/requests/:uuid/?' do
    logger.debug "GtkSrv: entered PUT /requests with params=#{params}"
    @request = Request.find params[:uuid]
    
    if @request.update_all(params)
      logger.debug "GtkSrv: returning PUT /requests with updated request=#{@request}"
      halt 200, @request.to_json
    else
      logger.debug "GtkSrv: returning PUT /requests with 'GtkSrv: Not possible to update the request'"
      json_error 400, 'GtkSrv: Not possible to update the request'
    end 
  end  

  private 
  def query_string
    request.env['QUERY_STRING'].nil? ? '' : '?' + request.env['QUERY_STRING'].to_s
  end

  def request_url
    log_message = 'GtkApi::request_url'
    logger.debug(log_message) {"Schema=#{request.env['rack.url_scheme']}, host=#{request.env['HTTP_HOST']}, path=#{request.env['REQUEST_PATH']}"}
    request.env['rack.url_scheme']+'://'+request.env['HTTP_HOST']+request.env['REQUEST_PATH']
  end
  
  class Hash
    def deep_stringify_keys
      deep_transform_keys{ |key| key.to_s }
    end
    def deep_transform_keys(&block)
      _deep_transform_keys_in_object(self, &block)
    end
    def _deep_transform_keys_in_object(object, &block)
      case object
      when Hash
        object.each_with_object({}) do |(key, value), result|
          result[yield(key)] = _deep_transform_keys_in_object(value, &block)
        end
      when Array
        object.map {|e| _deep_transform_keys_in_object(e, &block) }
      else
        object
      end
    end
  end
end
