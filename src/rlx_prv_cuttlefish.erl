%% -*- mode: erlang; tab-width: 4; indent-tabs-mode: 1; st-rulers: [70] -*-
%% vim: ts=4 sw=4 ft=erlang noet
-module(rlx_prv_cuttlefish).

-export([init/1, do/1, format_error/1]).

init(State) ->
	{ok, State}.

do(State0) ->
	case rlx_state:get(State0, post_overlay, false) of
		false ->
			{ok, State0};
		Overlays ->
			{RelName, RelVsn} = rlx_state:default_configured_release(State0),
			Release = rlx_state:get_realized_release(State0, RelName, RelVsn),
			OutputDir = rlx_state:output_dir(State0),
			ReleaseDir = filename:join([OutputDir, "releases", rlx_release:vsn(Release)]),
			{ok, State1} = cleanup_release(State0, Overlays, Release, OutputDir, ReleaseDir),
			{ok, State2} = cuttlefish_release(State1, Overlays, Release, OutputDir, ReleaseDir),
			{ok, State2}
	end.

format_error(Reason) ->
	io_lib:format("Error in ~p: ~p~n", [?MODULE, Reason]).

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
cleanup_release(State0, Overlays, Release, OutputDir, ReleaseDir) ->
	Prefix = code:root_dir(),
	ErtsVersion = rlx_release:erts(Release),
	LocalErts = filename:join([OutputDir, "erts-" ++ ErtsVersion]),
	ok = ec_file:copy(
		filename:join([Prefix, "bin", "start_clean.boot"]),
		filename:join([LocalErts, "bin", "start_clean.boot"])
	),
	_ = file:delete(filename:join([ReleaseDir, "sys.config"])), %% unused file
	_ = file:delete(filename:join([ReleaseDir, "vm.args"])), %% unused file
	State1 = rlx_state:put(State0, overlay, Overlays),
	rlx_prv_overlay:do(State1).

%% @private
cuttlefish_release(State, Overlays, Release, OutputDir, _ReleaseDir) ->
	case rlx_state:get(State, cuttlefish, false) of
		false ->
			{ok, State};
		true ->
			SchemaOverlays = lists:filter(fun(Overlay) ->
				element(1, Overlay) =:= template andalso filename:extension(element(3, Overlay)) =:= ".schema"
			end, Overlays),
			Schemas = lists:sort(fun(A,B) -> filename:basename(A) > filename:basename(B) end, [
				lists:flatten(filename:join(OutputDir, element(3, Schema)))
			|| Schema <- SchemaOverlays]),
			% io:format("Schemas: ~p~n", [Schemas]),
			case cuttlefish_schema:files(Schemas) of
				{error, Reason} ->
					{error, Reason};
				{_Translations, Mappings, _Validators} ->
					Filename = filename:join([OutputDir, "etc", atom_to_list(rlx_release:name(Release)) ++ ".conf"]),
					_ = cuttlefish_conf:generate_file(Mappings, Filename),
					{ok, State}
			end
	end.
