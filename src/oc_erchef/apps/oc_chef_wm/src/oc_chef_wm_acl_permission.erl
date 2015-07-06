%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92-*-
%% ex: ts=4 sw=4 et
%% @author Douglas Triggs <doug@chef.io>
%% @author Mark Mzyk <mm@chef.io>
%% Copyright 2014-2015 Chef Software, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%

-module(oc_chef_wm_acl_permission).

-include("../../include/oc_chef_wm.hrl").

%% Webmachine resource callbacks
-mixin([{oc_chef_wm_base, [content_types_accepted/2,
                           content_types_provided/2,
                           finish_request/2,
                           malformed_request/2,
                           ping/2,
                           post_is_create/2,
                           forbidden/2,
                           is_authorized/2,
                           service_available/2]}]).
-export([allowed_methods/2,
         from_json/2]).

%% chef_wm behaviour callbacks
-behaviour(chef_wm).
-export([
         auth_info/2,
         init/1,
         init_resource_state/1,
         malformed_request_message/3,
         request_type/0,
         validate_request/3
        ]).


init(Config) ->
    oc_chef_wm_base:init(?MODULE, Config).

init_resource_state(Config) ->
    AclType = ?gv(acl_object_type, Config),
    {ok, #acl_state{type = AclType}}.

request_type() ->
    "acl".

allowed_methods(Req, State) ->
    {['PUT'], Req, State}.

-spec validate_request(chef_wm:http_verb(), wm_req(), chef_wm:base_state()) ->
                              {wm_req(), chef_wm:base_state()}.
validate_request('PUT', Req, #base_state{chef_db_context = DbContext,
                                         organization_guid = OrgId,
                                         resource_state = #acl_state{type = Type} =
                                             AclState} = State) ->
    Body = wrq:req_body(Req),
    Ace = chef_json:decode_body(Body),
    Part = list_to_binary(wrq:path_info(acl_permission, Req)),
    %% Make sure we have valid json before trying other checks
    %% Throws if invalid json is found
    check_json_validity(Part, Ace),
    %% validate_authz_id will populate the ACL AuthzId, which is needed
    %% for checking the ACL constraints; we need to run validate_authz_id
    %% anyway, so go ahead and do so
    {Req1, State1 = #base_state{resource_state = #acl_state{
          authz_id = AuthzId}}} =
                                  oc_chef_wm_acl:validate_authz_id(Req, State,
                                                                   AclState#acl_state{acl_data = Ace},
                                                                    Type, OrgId,  DbContext),

    %% Check if we're violating any constraints around modifying ACLs
    %% i.e. deleting default groups, etc.
    case oc_chef_authz_acl_constraints:check_acl_constraints(AuthzId, Type, Part, Ace) of
      ok ->
        {Req1, State1};
      [ Violation | _T ] ->
        %% Received one or more failures. Report back the first one.
        throw({acl_constraint_violation, Violation})
    end.

auth_info(Req, State) ->
    oc_chef_wm_acl:check_acl_auth(Req, State).

from_json(Req, #base_state{organization_guid = OrgId,
                           resource_state = AclState} = State) ->
    Part = wrq:path_info(acl_permission, Req),
    case update_from_json(AclState, Part, OrgId) of
        forbidden ->
            {{halt, 400}, Req, State};
        bad_actor ->
            % We don't actually know which one, so can't use a more specific
            % message without checking every single object (which we don't yet
            % do efficiently); we only get back a list of Ids that has a
            % different length than the list of names we started with.
            Msg = <<"Invalid/missing actor in request body">>,
            Msg1 = {[{<<"error">>, [Msg]}]},
            Req1 = wrq:set_resp_body(chef_json:encode(Msg1), Req),
            {{halt, 400}, Req1, State#base_state{log_msg = bad_actor}};
        bad_group ->
            Msg = <<"Invalid/missing group in request body">>,
            Msg1 = {[{<<"error">>, [Msg]}]},
            Req1 = wrq:set_resp_body(chef_json:encode(Msg1), Req),
            {{halt, 400}, Req1, State#base_state{log_msg = bad_group}};
        _Other ->
            % So we return 200 instead of 204, for backwards compatibility:
            Req1 = wrq:set_resp_body(<<"{}">>, Req),
            {true, Req1, State}
    end.

%% Internal functions

check_json_validity(Part, Ace) ->
  case chef_object_base:strictly_valid(acl_spec(Part), [Part], Ace) of
    ok ->
      ok;
    Other ->
      throw(Other)
  end.

acl_spec(Part) ->
    {[
      {Part,
       {[
         {<<"actors">>, {array_map, string}},
         {<<"groups">>, {array_map, string}}
        ]}}
     ]}.


update_from_json(#acl_state{type = Type, authz_id = AuthzId, acl_data = Data},
                 Part, OrgId) ->
    try
        oc_chef_authz_acl:update_part(Part, Data, Type, AuthzId, OrgId)
    catch
        throw:forbidden ->
            forbidden;
        throw:bad_actor ->
            bad_actor;
        throw:bad_group ->
            bad_group
    end.

malformed_request_message(Any, _Req, _State) ->
    error({unexpected_malformed_request_message, Any}).
