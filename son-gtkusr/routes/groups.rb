##
## Copyright (c) 2015 SONATA-NFV
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
## Neither the name of the SONATA-NFV
## nor the names of its contributors may be used to endorse or promote
## products derived from this software without specific prior written
## permission.
##
## This work has been performed in the framework of the SONATA project,
## funded by the European Commission under Grant number 671517 through
## the Horizon 2020 and 5G-PPP programmes. The authors would like to
## acknowledge the contributions of their colleagues of the SONATA
## partner consortium (www.sonata-nfv.eu).

require 'json'
require 'sinatra'
require 'net/http'
require_relative '../helpers/init'

# Adapter-Keycloak API class
class Keycloak < Sinatra::Application
  # Get a group by query
  get '/groups/?' do
    logger.debug 'Adapter: entered GET /groups'
    # Return if Authorization is invalid
    # json_error(400, 'Authorization header not set') unless request.env["HTTP_AUTHORIZATION"]
    queriables = %w(id name)
    keyed_params = keyed_hash(params)
    keyed_params.each { |k, v|
      logger.debug "Adapter: query #{k}=#{v}"
      unless queriables.include? k
        json_error(400, 'Bad query')
      end
    }
    code, realm_groups = get_groups(keyed_params)
    logger.debug "Adapter: gathered groups #{realm_groups}"

    params['offset'] ||= DEFAULT_OFFSET
    params['limit'] ||= DEFAULT_LIMIT
    realm_groups = apply_limit_and_offset(JSON.parse(realm_groups), offset=params[:offset], limit=params[:limit])
    halt code.to_i, {'Content-type' => 'application/json'}, realm_groups.to_json
  end

  # post '/groups/new/?' do
  post '/groups/?' do
    # POST /admin/realms/{realm}/groups
    # BodyParameter GroupRepresentation
    logger.debug 'Adapter: entered POST /groups'
    # logger.info "Content-Type is " + request.media_type
    #halt 415 unless (request.content_type == 'application/json')

    new_group_data, errors = parse_json(request.body.read)
    halt 400, {'Content-type' => 'application/json'}, errors.to_json if errors
    halt 400 unless new_group_data.is_a?(Hash)

    code, msg = create_group(new_group_data) # .to_json)
    logger.debug "CODE #{code}"
    logger.debug "MESSAGE #{msg}"
    halt code, {'Content-type' => 'application/json'}, msg.to_json
  end

  put '/groups/?' do
    logger.debug 'Adapter: entered PUT /groups'
    # PUT /admin/realms/{realm}/groups/{id}
    # BodyParameter GroupRepresentation
    logger.info "Content-Type is " + request.media_type
    halt 415 unless (request.content_type == 'application/json')

    queriables = %w(id name)
    logger.debug "params=#{params}"
    json_error(400, 'Group Name or Id are missing') if params.empty?
    keyed_params = keyed_hash(params)


    keyed_params.each { |k, v|
      logger.debug "Adapter: query #{k}=#{v}"
      unless queriables.include? k
        json_error(400, 'Bad query')
      end
    }
    code, group_data = get_groups(keyed_params)
    logger.debug "Adapter: found group_data= #{group_data}"
    group_data, errors = parse_json(group_data)

    new_group_data, errors = parse_json(request.body.read)
    halt 400, {'Content-type' => 'application/json'}, errors.to_json if errors
    halt 400 unless new_group_data.is_a?(Hash)

    code, msg = update_group(group_data['id'], new_group_data.to_json)
    halt code, {'Content-type' => 'application/json'}, msg
  end

  delete '/groups/?' do
    logger.debug 'Adapter: entered DELETE /groups'
    # DELETE /admin/realms/{realm}/groups/{id}
    # Return if Authorization is invalid
    # json_error(400, 'Authorization header not set') unless request.env["HTTP_AUTHORIZATION"]
    queriables = %w(id name)
    json_error(400, 'Group Name or Id are missing') if params.empty?
    keyed_params = keyed_hash(params)

    keyed_params.each { |k, v|
      logger.debug "Adapter: query #{k}=#{v}"
      unless queriables.include? k
        json_error(400, 'Bad query')
      end
    }
    code, group_data = get_groups(keyed_params)
    logger.debug "Adapter: found group_data= #{group_data}"
    group_data, errors = parse_json(group_data)

    code, msg = update_group(group_data['id'])
    halt code, {'Content-type' => 'application/json'}, msg
  end

  post '/groups/assign/?' do
    # Assign user to a group
    logger.debug 'Adapter: entered POST /groups/assign'
    logger.info "Content-Type is " + request.media_type
    halt 415 unless (request.content_type == 'application/json')

    form, errors = parse_json(request.body.read)
    halt 400, {'Content-type' => 'application/json'}, errors.to_json if errors
    halt 400 unless form.is_a?(Hash)
    json_error 400, 'Username not provided' unless form.key?('username')
    json_error 400, 'Group name not provided' unless form.key?('group')

    #Translate from username to User_id
    user_id = get_user_id(form['username'])
    json_error 404, 'Username not found' if user_id.nil?

    code , msg = assign_group(form['group'], user_id)
    halt code, {'Content-type' => 'application/json'}, msg
  end

  post '/groups/unassign/?' do
    # Unassign user to a group
    logger.debug 'Adapter: entered POST /groups/unassign'
    logger.info "Content-Type is " + request.media_type
    halt 415 unless (request.content_type == 'application/json')

    form, errors = parse_json(request.body.read)
    halt 400, {'Content-type' => 'application/json'}, errors.to_json if errors
    halt 400 unless form.is_a?(Hash)
    json_error 400, 'Username not provided' unless form.key?('username')
    json_error 400, 'Group name not provided' unless form.key?('group')

    #Translate from username to User_id
    user_id = get_user_id(form['username'])
    json_error 404, 'Username not found' if user_id.nil?

    code , msg = unassign_group(form['group'], user_id)
    halt code, {'Content-type' => 'application/json'}, msg
  end
end