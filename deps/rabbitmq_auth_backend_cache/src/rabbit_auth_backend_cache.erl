%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_auth_backend_cache).
-include_lib("rabbit_common/include/rabbit.hrl").

-behaviour(rabbit_authn_backend).
-behaviour(rabbit_authz_backend).

-export([user_login_authentication/2, user_login_authorization/1,
         check_vhost_access/3, check_resource_access/3]).

%% Implementation of rabbit_auth_backend

user_login_authentication(Username, AuthProps) ->
    with_cache({user_login_authentication, [Username, AuthProps]},
        fun({ok, _})      -> success;
           ({refused, _}) -> refusal;
           ({error, _} = Err) -> Err
        end).

user_login_authorization(Username) ->
    with_cache({user_login_authorization, [Username]},
        fun({ok, _})      -> success;
           ({ok, _, _})   -> success;
           ({refused, _}) -> refusal;
           ({error, _} = Err) -> Err
        end).

check_vhost_access(#auth_user{} = AuthUser, VHostPath, Sock) ->
    with_cache({check_vhost_access, [AuthUser, VHostPath, Sock]},
        fun(true)  -> success;
           (false) -> refusal;
           ({error, _} = Err) -> Err
        end).

check_resource_access(#auth_user{} = AuthUser,
                      #resource{} = Resource, Permission) ->
    with_cache({check_resource_access, [AuthUser, Resource, Permission]},
        fun(true)  -> success;
           (false) -> refusal;
           ({error, _} = Err) -> Err
        end).

with_cache({F, A}, Fun) ->
    {ok, AuthCache} = application:get_env(rabbitmq_auth_backend_cache,
                                          cache_module),
    case AuthCache:get({F, A}) of
        {ok, Result} ->
            Result;
        {error, not_found} ->
            {ok, Backend} = application:get_env(rabbitmq_auth_backend_cache,
                                                cached_backend),
            {ok, TTL} = application:get_env(rabbitmq_auth_backend_cache,
                                            cache_ttl),
            BackendResult = apply(Backend, F, A),
            case should_cache(BackendResult, Fun) of
                true  -> ok = AuthCache:put({F, A}, BackendResult, TTL);
                false -> ok
            end,
            BackendResult
    end.

should_cache(Result, Fun) ->
    {ok, CacheRefusals} = application:get_env(rabbitmq_auth_backend_cache,
                                              cache_refusals),
    case {Fun(Result), CacheRefusals} of
        {success, _}    -> true;
        {refusal, true} -> true;
        _               -> false
    end.
