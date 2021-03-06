REBAR = ./rebar
LIBS = ERL_LIBS=apps:deps

all: compile

compile:
	@$(REBAR) compile

deps:
	@$(REBAR) get-deps

clean:
	@$(REBAR) clean
	rm -f erl_crash.dump
	rm -f rel/erl_crash.dump

test: compile
	@$(REBAR) eunit skip_deps=true
	@$(REBAR) xref skip_deps=true

release: test
	@$(REBAR) generate

# for testing purposes
run:
	@$(REBAR) compile skip_deps=true
	test -e netspire.conf || cp rel/priv/netspire.conf.sample netspire.conf
	test -e tariffs.conf || cp rel/priv/tariffs.conf.sample tariffs.conf
	$(LIBS) erl -name netspire -netspire logfile \"/tmp/netspire.log\" \
		-mnesia dir \"/tmp/netspire\" \
		-mnesia dump_log_write_threshold 50000 \
		-mnesia dc_dump_limit 40 \
		-sasl errlog_type error \
		-s netspire

PHONY: deps
