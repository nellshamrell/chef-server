SHELL := /bin/bash

PROJ = oc_erchef
DEVVM_PROJ = opscode-erchef

ALL_HOOK = bundle
CLEAN_HOOK = bundle_clean
REL_HOOK = compile bundle

CT_DIR = common_test

DIALYZER_OPTS =

DIALYZER_SRC = -r apps/chef_db/ebin -r apps/chef_index/ebin -r apps/chef_objects/ebin -r apps/depsolver/ebin -r apps/oc_chef_authz/ebin -r apps/oc_chef_wm/ebin
DIALYZER_SKIP_DEPS = couchbeam

ct: clean_ct compile
	time $(REBARC) ct skip_deps=true

ct_fast: clean_ct
	time $(REBARC) compile ct skip_deps=true

# Runs a specific test suite
# e.g. make ct_deliv_hand_user_authn
# supports a regex as argument, as long as it only matches one suite

APPS = $(notdir $(wildcard apps/*))

ct_%: clean_ct
	@ EXTRAS=$$(if [ -f "$(CT_DIR)/$*_SUITE.erl" ]; then \
		echo "$*"; \
	else \
		FIND_RESULT=$$(find "." -name "*$**_SUITE\.erl"); \
		[ -z "$$FIND_RESULT" ] && echo "No suite found with input '$*'" 1>&2 && exit 1; \
		NB_MACTHES=$$(echo "$$FIND_RESULT" | wc -l) && [[ $$NB_MACTHES != "       1" ]] && echo -e "Found $$NB_MACTHES suites matching input:\n$$FIND_RESULT" 1>&2 && exit 1; \
		SUITE=$$(echo "$$FIND_RESULT" | perl -wlne 'print $$1 if /\/([^\/]+)_SUITE\.erl/') && \
		APP=$$(echo "$$FIND_RESULT" | perl -wlne 'print $$1 if /\.\/apps\/([^\/]+)\/.*\/[^\/]+_SUITE\.erl/') && \
		SKIP_APPS=$$(echo "$(APPS)" | sed "s/$$APP//" | sed -E "s/[ ]+/,/g") && \
		echo "suites=$$SUITE skip_apps=$$SKIP_APPS"; \
	fi) && COMMAND="time $(REBAR) ct $$EXTRAS skip_deps=true" && echo $$COMMAND && eval $$COMMAND;

clean_ct:
	@rm -f $(CT_DIR)/*.beam
	@rm -rf logs

## Pull in devvm.mk for relxy goodness
include devvm.mk

bundle_clean:
	@cd apps/chef_objects/priv/depselector_rb; rm -rf .bundle

bundle:
	@echo bundling up depselector, This might take a while...
	@cd apps/chef_objects/priv/depselector_rb; bundle install --deployment --path .bundle

### These are targets specific to the travis environment that allow us to
### cache   the libgecode installation, avoiding the need to rebuild it every time.

GECODE_VERSION?=3.7.3

GECODE_FILE=gecode-$(GECODE_VERSION).tar.gz
GECODE_SRC_DIR=gecode-$(GECODE_VERSION)
GECODE_LIB_DIR=libgecode/$(GECODE_VERSION)/lib
GECODE_URL=http://www.gecode.org/download/$(GECODE_FILE)

ifeq ($(TRAVIS),true)
ifeq "$(wildcard $(GECODE_LIB_DIR))" ""
GECODE_INSTALL := install_libgecode
else
GECODE_INSTALL := no_gecode_needed
endif
else
GECODE_INSTALL := no_gecode_without_travis
endif

no_gecode_needed:
	@echo "You already have $(GECODE_LIB_DIR), bypassing make and install"

no_gecode_without_travis:
	@echo "Bypassing gecode install for non-travis build"

download_libgecode:
	@echo "Downloading libgecode sources from $(GECODE_URL)"
	-wget $(GECODE_URL)

extract_libgecode: download_libgecode
	@tar xf $(GECODE_FILE)

configure_libgecode: extract_libgecode
	cd $(GECODE_SRC_DIR) && ./configure --prefix=$(GECODE_LIB_DIR) --disable-doc-dot --disable-doc-serach --disable-doc-tagfile --disable-doc-chm --disable-docset --disable-qt --disable-examples --disable-flatzinca

build_libgecode: configure_libgecode
	cd $(GECODE_SRC_DIR) && $(MAKE)

install_libgecode: build_libgecode
	cd $(GECODE_SRC_DIR) && $(MAKE) install

install: $(GECODE_INSTALL)
	@./rebar get-deps -C rebar.config.lock
blarg:
	echo "$(GECODE_INSTALL)"
travis: all
	 PATH=~/perl5/bin:$(PATH) $(REBARC) skip_deps=true ct

DEVVM_DIR = $(DEVVM_ROOT)/_rel/oc_erchef
