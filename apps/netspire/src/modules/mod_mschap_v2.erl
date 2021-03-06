-module(mod_mschap_v2).

-behaviour(gen_module).

%% API
-export([verify_mschap_v2/6]).

%% Needs for EAP-MSCHAPv2
-export([mschap_v2_challenge_hash/3, mschap_v2_challenge_response/2,
         mschap_v2_auth_response/3]).

%% gen_module callbacks
-export([start/1, stop/0]).

-include("radius.hrl").
-include("netspire.hrl").

start(_Options) ->
    ?INFO_MSG("Starting dynamic module ~p~n", [?MODULE]),
    netspire_hooks:add(radius_auth, ?MODULE, verify_mschap_v2).

stop() ->
    ?INFO_MSG("Stopping dynamic module ~p~n", [?MODULE]),
    netspire_hooks:delete(radius_auth, ?MODULE, verify_mschap_v2).

verify_mschap_v2(_, Request, UserName, Password, Replies, Client) ->
    case radius:attribute_value("MS-CHAP-Challenge", Request) of
        undefined -> undefined;
        ChapChallenge ->
            case radius:attribute_value("MS-CHAP2-Response", Request) of
                undefined ->
                    Request;
                Value ->
                    Auth = Request#radius_packet.auth,
                    Secret = Client#nas_spec.secret,
                    ChapResponse = list_to_binary(Value),
                    do_mschap_v2(UserName, ChapChallenge, ChapResponse, Password, Replies, Auth, Secret)
            end
    end.

do_mschap_v2(UserName, ChapChallenge, ChapResponse, Password, Replies, Auth, Secret) ->
    Password1 = util:latin1_to_unicode(Password),
    PasswordHash = crypto:md4(Password1),
    NTResponse = mschap_v2_nt_response(ChapResponse),
    PeerChallenge = mschap_v2_peer_challenge(ChapResponse),
    Challenge = mschap_v2_challenge_hash(PeerChallenge, ChapChallenge, UserName),
    ChallengeResponse = mschap_v2_challenge_response(Challenge, PasswordHash),

    case ChallengeResponse == NTResponse of
        true ->
            Ident = mschap_v2_ident(ChapResponse),
            AuthResponse = mschap_v2_auth_response(PasswordHash, NTResponse, Challenge),
            Chap2Success = [Ident] ++ AuthResponse,
            Attrs = [{"MS-CHAP2-Success", Chap2Success}],
            ?INFO_MSG("MS-CHAP-V2 authentication succeeded: ~p~n", [UserName]),
            case gen_module:get_option(?MODULE, use_mppe) of
                yes ->
                    MPPE = mschap_v2_mppe:mppe_attrs(NTResponse, PasswordHash, Auth, Secret),
                    MPPEOpts = mppe_opts(),
                    {stop, {accept, Replies ++ Attrs ++ MPPE ++ MPPEOpts}};
                _ ->
                    {stop, {accept, Replies ++ Attrs}}
            end;
        _ ->
            ?INFO_MSG("MS-CHAP-V2 authentication failed: ~p~n", [UserName]),
            {stop, {reject, []}}
    end.

mschap_v2_challenge_response(Challenge, PasswordHash) ->
    Keys = split_password_hash(<<PasswordHash/binary, 0, 0, 0, 0, 0>>),
    Cyphers = [crypto:des_ecb_encrypt(K, Challenge) || K <- Keys],
    list_to_binary(Cyphers).

split_password_hash(<<A:7/binary-unit:8, B:7/binary-unit:8, C:7/binary-unit:8>>) ->
    lists:map(fun set_parity/1, [A, B, C]).

mschap_v2_challenge_hash(PeerChallenge, AuthChallenge, UserName) ->
    ShaContext = crypto:sha_init(),
    ShaContext1 = crypto:sha_update(ShaContext, PeerChallenge),
    ShaContext2 = crypto:sha_update(ShaContext1, AuthChallenge),
    ShaContext3 = crypto:sha_update(ShaContext2, UserName),
    Digest = crypto:sha_final(ShaContext3),
    <<Challenge:8/binary-unit:8, _/binary>> = Digest,
    Challenge.

mschap_v2_auth_response(PasswordHash, NTResponse, Challenge) ->
    PasswordHashHash = crypto:md4(PasswordHash),
    ShaContext = crypto:sha_init(),
    ShaContext1 = crypto:sha_update(ShaContext, PasswordHashHash),
    ShaContext2 = crypto:sha_update(ShaContext1, NTResponse),
    ShaContext3 = crypto:sha_update(ShaContext2, mschap_v2_magic1()),
    Digest = crypto:sha_final(ShaContext3),

    ShaContext4 = crypto:sha_init(),
    ShaContext5 = crypto:sha_update(ShaContext4, Digest),
    ShaContext6 = crypto:sha_update(ShaContext5, Challenge),
    ShaContext7 = crypto:sha_update(ShaContext6, mschap_v2_magic2()),
    Digest1 = crypto:sha_final(ShaContext7),
    "S=" ++ util:binary_to_hex_string(Digest1).

mschap_v2_peer_challenge(<<_:16, Challenge:16/binary-unit:8, _Rest/binary>>) ->
    Challenge.

mschap_v2_nt_response(<<_:208, NTResponse:24/binary-unit:8>>) ->
    NTResponse.

mschap_v2_ident(<<Ident:8, _Rest/binary>>) ->
    Ident.

mschap_v2_magic1() ->
    <<16#4D, 16#61, 16#67, 16#69, 16#63, 16#20, 16#73, 16#65, 16#72, 16#76,
      16#65, 16#72, 16#20, 16#74, 16#6F, 16#20, 16#63, 16#6C, 16#69, 16#65,
      16#6E, 16#74, 16#20, 16#73, 16#69, 16#67, 16#6E, 16#69, 16#6E, 16#67,
      16#20, 16#63, 16#6F, 16#6E, 16#73, 16#74, 16#61, 16#6E, 16#74>>.

mschap_v2_magic2() ->
    <<16#50, 16#61, 16#64, 16#20, 16#74, 16#6F, 16#20, 16#6D, 16#61, 16#6B,
      16#65, 16#20, 16#69, 16#74, 16#20, 16#64, 16#6F, 16#20, 16#6D, 16#6F,
      16#72, 16#65, 16#20, 16#74, 16#68, 16#61, 16#6E, 16#20, 16#6F, 16#6E,
      16#65, 16#20, 16#69, 16#74, 16#65, 16#72, 16#61, 16#74, 16#69, 16#6F,
      16#6E>>.

set_parity(Bin) ->
  set_parity(Bin, 0, 0, <<>>).

set_parity(<<>>, _, Next, Output) ->
  Result = Next bor 1,
  <<Output/binary, Result>>;
set_parity(<<Current:8, Rest/binary>>, I, Next, Output) ->
  Result = (Current bsr I) bor Next bor 1,
  set_parity(Rest, I + 1, Current bsl (7 - I), <<Output/binary, Result>>).

mppe_opts() ->
    Policy = case gen_module:get_option(?MODULE, require_encryption) of
        yes ->
            % Encryption required
            [{"MS-MPPE-Encryption-Policy", <<2:32>>}];
        _ ->
            % Encryption allowed
            [{"MS-MPPE-Encryption-Policy", <<1:32>>}]
    end,
    Types = case gen_module:get_option(?MODULE, require_strong) of
        yes ->
            % 128 bit keys
            [{"MS-MPPE-Encryption-Types", <<4:32>>}];
        _ ->
            % 40- or 128-bit keys may be used
            [{"MS-MPPE-Encryption-Types", <<6:32>>}]
    end,
    Policy ++ Types.
