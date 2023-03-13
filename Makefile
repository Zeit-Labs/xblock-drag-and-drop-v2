.PHONY: clean help compile_translations dummy_translations extract_translations detect_changed_source_translations \
		build_dummy_translations validate_translations pull_translations push_translations check_translations_up_to_date \
		install_firefox requirements selfcheck test test.python test.unit test.quality upgrade mysql

.DEFAULT_GOAL := help

WORKING_DIR := drag_and_drop_v2
JS_TARGET := $(WORKING_DIR)/public/js/translations
EXTRACT_DIR := $(WORKING_DIR)/conf/locale/en/LC_MESSAGES
EXTRACTED_DJANGO := $(EXTRACT_DIR)/django-partial.po
EXTRACTED_DJANGOJS := $(EXTRACT_DIR)/djangojs-partial.po
EXTRACTED_TEXT := $(EXTRACT_DIR)/text.po

FIREFOX_VERSION := "43.0"

help: ## display this help message
	@echo "Please use \`make <target>' where <target> is one of"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}'

clean: ## remove generated byte code, coverage reports, and build artifacts
	find . -name '__pycache__' -exec rm -rf {} +
	find . -name '*.pyc' -exec rm -f {} +
	find . -name '*.pyo' -exec rm -f {} +
	find . -name '*~' -exec rm -f {} +
	rm -fr build/
	rm -fr dist/
	rm -fr *.egg-info

## Localization targets

extract_translations: ## extract strings to be translated, outputting .po files
	cd $(WORKING_DIR) && i18n_tool extract
	mv $(EXTRACTED_DJANGO) $(EXTRACTED_TEXT)
	tail -n +20 $(EXTRACTED_DJANGOJS) >> $(EXTRACTED_TEXT)
	rm $(EXTRACTED_DJANGOJS)
	sed -i'' -e 's/nplurals=INTEGER/nplurals=2/' $(EXTRACTED_TEXT)
	sed -i'' -e 's/plural=EXPRESSION/plural=\(n != 1\)/' $(EXTRACTED_TEXT)

compile_translations: ## compile translation files, outputting .mo files for each supported language
	cd $(WORKING_DIR) && i18n_tool generate -v
	python manage.py compilejsi18n --namespace DragAndDropI18N --output $(JS_TARGET)

detect_changed_source_translations:
	cd $(WORKING_DIR) && i18n_tool changed

dummy_translations: ## generate dummy translation (.po) files
	cd $(WORKING_DIR) && i18n_tool dummy

build_dummy_translations: dummy_translations compile_translations ## generate and compile dummy translation files

validate_translations: build_dummy_translations detect_changed_source_translations ## validate translations

pull_translations: ## pull translations from transifex
	tx pull -t -a -f --mode reviewed --minimum-perc=1

push_translations: ## push translations to transifex
	tx push -s

check_translations_up_to_date: extract_translations compile_translations dummy_translations detect_changed_source_translations ## extract, compile, and check if translation files are up-to-date

install_firefox:
	@mkdir -p test_helpers
	@test -f ./test_helpers/firefox/firefox && echo "Firefox already installed." || \
	(cd test_helpers && \
	wget -N "https://archive.mozilla.org/pub/firefox/releases/$(FIREFOX_VERSION)/linux-x86_64/en-US/firefox-$(FIREFOX_VERSION).tar.bz2" && \
	tar -xjf firefox-$(FIREFOX_VERSION).tar.bz2)

piptools: ## install pinned version of pip-compile and pip-sync
	pip install -r requirements/pip.txt
	pip install -r requirements/pip-tools.txt

requirements: piptools  ## install test requirements locally
	pip-sync requirements/ci.txt

requirements_python: install_firefox piptools  ## install all requirements locally
	pip-sync requirements/dev.txt requirements/private.*

test.quality: selfcheck ## run quality checkers on the codebase
	tox -e quality

test.python: ## run python unit and integration tests
	PATH=test_helpers/firefox:$$PATH xvfb-run python run_tests.py $(TEST)

test.unit: ## run all unit tests
	tox -- $(TEST)

test.integration: ## run all integration tests
	tox -e integration -- $(TEST)

test: test.unit test.integration test.quality ## Run all tests
	tox -e translations

# Define PIP_COMPILE_OPTS=-v to get more information during make upgrade.
PIP_COMPILE = pip-compile --upgrade --resolver=backtracking $(PIP_COMPILE_OPTS)

upgrade: export CUSTOM_COMPILE_COMMAND=make upgrade
upgrade: ## update the requirements/*.txt files with the latest packages satisfying requirements/*.in
	pip install -qr requirements/pip-tools.txt
	# Make sure to compile files after any other files they include!
	$(PIP_COMPILE) --allow-unsafe -o requirements/pip.txt requirements/pip.in
	$(PIP_COMPILE) -o requirements/pip-tools.txt requirements/pip-tools.in
	pip install -qr requirements/pip.txt
	pip install -qr requirements/pip-tools.txt
	$(PIP_COMPILE) -o requirements/base.txt requirements/base.in
	$(PIP_COMPILE) -o requirements/test.txt requirements/test.in
	$(PIP_COMPILE) -o requirements/quality.txt requirements/quality.in
	$(PIP_COMPILE) -o requirements/workbench.txt requirements/workbench.in
	$(PIP_COMPILE) -o requirements/ci.txt requirements/ci.in
	$(PIP_COMPILE) -o requirements/dev.txt requirements/dev.in

mysql: ## run mysql database for integration tests
	docker run --rm -it --name mysql -p 3307:3306 -e MYSQL_ROOT_PASSWORD=rootpw -e MYSQL_DATABASE=db mysql:8

selfcheck: ## check that the Makefile is well-formed
	@echo "The Makefile is well-formed."
