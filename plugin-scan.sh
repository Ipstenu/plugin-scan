#!/bin/sh

# This script scans plugins for the usual drama. It's not going to catch
#  everything. It can't. But it can, and will, catch most simple problems.
#
# ./plugin-scan.sh FILENAME.ZIP
# ./plugin-scan.sh URL_TO_ZIP

if (( $BASH_VERSINFO < 4)); 
then 
	echo -e "ERROR! Upgrade Bash. Sorry, gotta be 4+."
	exit 1
fi

# Validate all Parameters are present
if [[ ! $1 ]]
then
	echo -e "ERROR: No file defined."
	exit 1
fi

if [[ $1 =~ \.zip$ ]]
then
	if [[ $1 == http* ]]
	then
		echo -e "DOWNLOADING FILE"
		wgot=$(basename "$1")
		if [[ -f "$wgot" ]]
		then
			timestamp=$(date +%s)
			wgot="$timestamp-$wgot"
			wget $1 -q -O $wgot
		else
			wget $1 -q
		fi
		zip=$wgot
	else
		zip=$1
	fi
else
	if [[ -s $1.zip ]]
	then
		zip=$1.zip
	else
		echo -e "ERROR: File does not exist or is not a zip."
		exit 1
	fi
fi

if [[ ! $2 ]];then
	param=default
else
	for validparam in echo phpcs force
	do
		if [[ $2 = $validparam ]];then
			param=$validparam
		fi
	done
fi

echo -e "UNZIPPING FILE ..."
unzip -qq "$zip" -d current_plugin

if [ ! -d "current_plugin" ]
	then
		echo -e "ERROR: Unzip failed."
		exit 1
fi

if [ -d "current_plugin/__MACOSX/" ]
	then
		rm -rf current_plugin/__MACOSX/
fi

if [ -f "current_plugin/.DS_Store" ]
	then
		rm -rf current_plugin/.DS_Store
fi

echo -e "BEGINNING SCAN ..."

## Do we die?
stopevil=false

## Create Files
filename=${zip%.*}-review-$param.php
tempfile=${zip%.*}-temp.txt
phpcsfile=${zip%.*}-phpcs.txt
touch "$filename"
echo -e "<?php" >> "$filename"
echo -e "\n\nScanning "$zip" -- $(date)" >> "$filename"

## Do the checks

# People attempting to PoC
ag --path-to-ignore $0.ignore --skip-vcs-ignores 'This is Testing for poc' current_plugin/ >> "$tempfile"
if [[ -s "$tempfile" ]]
then
	echo -e "\n## DANGER! THIS PLUGIN IS TRYING TO TEST A 'PLUGIN CONFUSION' ISSUE. REJECT AND INFORM." >> "$filename"
	paste "$tempfile" >> "$filename"
	stopevil=true
fi

# Source Guardian code is not allowed
ag --path-to-ignore $0.ignore --skip-vcs-ignores 'sourceguardian.com' current_plugin/ >> "$tempfile"
ag --path-to-ignore $0.ignore --skip-vcs-ignores 'function_exists/(/'sg_load/'/)' current_plugin/ >> "$tempfile"
ag --path-to-ignore $0.ignore --skip-vcs-ignores '$__x=' current_plugin/ >> "$tempfile"
if [[ -s "$tempfile" ]]
then
	echo -e "\n## ALERT: Source Guardian is meant to HIDE the code from being read. Do not allow." >> "$filename"
	paste "$tempfile" >> "$filename"
	stopevil=true
fi
> "$tempfile"

# Note -- there is a whole lot of other examples here, but they list specific people who were banned so it's not available here.

if [[ "$param" = force ]];then
	stopevil=false
	param=default
fi

## If we made it past the evil people check, we do the rest.
if [ "$stopevil" = false ] && [ "$param" = default ]; then

	# applications don't belong but sometimes people get fonts and PHP set as applications.
	find ./current_plugin/ -type f -exec file --mime-type {}  \; | awk '{if ($NF == "application/octet-stream") print $0 }' >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## CAUTION: Application files are generally not permitted. See what's up." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Readme Missing
	find current_plugin -type f -iname "readme.txt" >> "$tempfile"
	if [[ ! -s "$tempfile" ]]
	then
		find current_plugin -type f -iname "readme.md" >> "$tempfile"
		if [[ ! -s "$tempfile" ]]
		then
			echo -e "\n## WARNING: No Readme TXT or MD found." >> "$filename"
		else
			readme=`find current_plugin -type f -iname "readme.md"`
		fi
	else
		readme=`find current_plugin -type f -iname "readme.txt"`
	fi
	> "$tempfile"

	# Readme Defaults commonly missed
	ag --path-to-ignore $0.ignore -G 'readme.txt' 'this should be a list of wordpress.org userid' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore -G 'readme.txt' 'Here is a short description of the plugin.' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## WARNING: readme.txt contains default content" >> "$filename"
	fi
	> "$tempfile"

	# Names
	ag -G 'readme.txt' '=== ' current_plugin/ >> "$tempfile"
	ag -G 'readme.md' '=== ' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "Plugin Name:" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## README: Check name for Trademarks" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Tested Up To
	echo -e "\n## README: Check Tested Up To Major Version" >> "$filename"
	ag -G 'readme.txt' 'tested up to:' current_plugin/ >> "$tempfile"
	ag -G 'readme.md' 'tested up to:' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		paste "$tempfile" >> "$filename"
	else
		echo -e "No 'Tested up to' value found in readme." >> "$filename"
	fi
	> "$tempfile"

	# Stable Tag
	echo -e "\n## README: Check stable tags (they should match the version and NOT be trunk)" >> "$filename"
	ag -G 'readme.txt' 'stable tag:' current_plugin/ >> "$tempfile"
	ag -G 'readme.md' 'stable tag:' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		paste "$tempfile" >> "$filename"
	else
		echo -e "No 'Stable Tag' value found in readme.txt." >> "$filename"
	fi
	> "$tempfile"

	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "version:" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		paste "$tempfile" >> "$filename"
	else
		echo -e "\nNo 'Version' value found in plugin headers." >> "$filename"
	fi
	> "$tempfile"

	# Stop people from trying to override the updater
	# https://make.wordpress.org/core/2021/06/29/introducing-update-uri-plugin-header-in-wordpress-5-8/
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "Update URI:" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Use of Update URI is not helpful in plugins hosted on .org, please remove." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Don't let people hurt users
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "ALLOW_UNFILTERED_UPLOADS" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Use of ALLOW_UNFILTERED_UPLOADS is disallowed." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Common 3rd Party resources that forgets to have licences
	for thirdparty in corona.lmao.ninja covid19api.com domo.com ipecho.com
	do
		ag --path-to-ignore $0.ignore --skip-vcs-ignores $thirdparty current_plugin/ >> "$tempfile"
	done
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## README: Third parties MUST have privacy notes in the readme." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Check to see if they call wordpress.org anywhere
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "wordpress.org" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## CHECK: Check to make sure .org calls are to their plugin and non-abusive" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	## BEGIN QUICK CHECKS

	# Referencing Automattic
	ag --php --path-to-ignore $0.ignore --skip-vcs-ignores "Automattic" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## CHECK: Namedropping A8C may be a copy/theft" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Including Woo-Includes Directory or the files.
	find current_plugin -type d -name "woo-includes" >> "$tempfile"
	ag --php --skip-vcs-ignores "woothemes_queue_update" current_plugin/ >> "$tempfile"
	ag --php --skip-vcs-ignores "woothemes_updater_install" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Woo-Includes folder is not needed" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Unicode UTF8
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "u00" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Unicode UTF-8 Obfuscation in PHP" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Unicode UTF8
	ag --path-to-ignore $0.ignore --js --files-with-matches "u00" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Unicode UTF-8 Obfuscation in JS" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Eval
	ag --path-to-ignore $0.ignore --php "eval(" -Q current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php "eval (" -Q current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: Eval should be avoided whenever possible (be aware for flase pos with JS)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# shell_exec
	ag --path-to-ignore $0.ignore --php "shell_exec" -Q current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: Shell EXEC should not be used" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Plugin Update Checker
	ag --skip-vcs-ignores "domain = 'plugin-update-checker';" current_plugin/ >> "$tempfile"
	find current_plugin -type f -name 'plugin-update-checker.php' >> "$tempfile"
	ag --skip-vcs-ignores "domain = 'WP_GitHub_Updater';" current_plugin/ >> "$tempfile"
	ag --skip-vcs-ignores "domain = 'WPGitHubUpdater';" current_plugin/ >> "$tempfile"
	ag --skip-vcs-ignores "class EDD_SL_Plugin_Updater" current_plugin/ >> "$tempfile"
	ag --skip-vcs-ignores "updater.wbbdev.com" current_plugin/ >> "$tempfile"
	ag --skip-vcs-ignores "site_transient_update_plugins" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Plugin Update Checker" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Touching updaters
	ag --path-to-ignore $0.ignore --skip-vcs-ignores "pre_set_site_transient_update_" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores "auto_update_plugin" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores "_site_transient_update_core" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: Plugin may be messing with updates." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# ionCube
	ag --path-to-ignore $0.ignore --skip-vcs-ignores "ionCube" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: ionCube" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Curl
	ag --path-to-ignore $0.ignore --skip-vcs-ignores "curl_exec" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Curl, use HTTP API" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# file_get_contents
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "file_get_contents" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: file_get_contents, use HTTP API" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# move_uploaded_file
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "move_uploaded_file" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: move_uploaded_file, use WP functions." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Create User
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "wp_create_user" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: wp_create_user is often used to make backdoor accounts" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# PACKER
	ag --path-to-ignore $0.ignore --skip-vcs-ignores "p,a,c,k" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: packer" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Zips
	find current_plugin -type f -name '*.zip' >> "$tempfile"
	find current_plugin -type f -name '*.gz' >> "$tempfile"
	find current_plugin -type f -name '*.tgz' >> "$tempfile"
	find current_plugin -type f -name '*.rar' >> "$tempfile"
  find current_plugin -type f -name "*.phar" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Contains Compressed file" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Powered·by
	ag -G --skip-vcs-ignores "powered·by" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Powered·by must be Opt IN" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# ACF Pro
	ag -G 'acf.php' 'Plugin Name: Advanced Custom Fields PRO' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NOT PERMITTED: Pro version of ACF, need to use free." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Losthost
	ag --path-to-ignore $0.ignore --php "http://localhost" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php "https://localhost" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: calling localhost" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Base64
	ag --path-to-ignore $0.ignore --php "base64_" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: base64" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# str_rot13
	ag --path-to-ignore $0.ignore --php "str_rot13" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: str_rot13" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# hex2bin
	ag --path-to-ignore $0.ignore --php "hex2bin" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: hex2bin" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# IFRAMES
	ag --path-to-ignore $0.ignore --php "<iframe" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: iframes are not allowed on Admin pages" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Sending email
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores "wp_mail" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: wp_mail may be used to track users" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# jQuery
	ag --path-to-ignore $0.ignore --js -l "jquery.org/license" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --js -l "jqueryui.com" current_plugin/ >> "$tempfile"
	find current_plugin -type f -name 'jquery-ui.js' >> "$tempfile"
	find current_plugin -type f -name 'jquery-ui.min.js' >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: jQuery already included in WP" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Offloaded Files
	for offload in googleapis.com code.jquery.com cdn.cloudflare.com cloudflare.com cdn.jsdelivr.net cdn.rawgit.com code.getmdl.io bootstrapcdn cl.ly cdn.datatables.net raw.githubusercontent.com unpkg.com imgur.com rawgit.com amazonaws.com cdn.tiny.cloud tiny.cloud tailwindcss.com
	do
		ag --width 200 --path-to-ignore $0.ignore --skip-vcs-ignores $offload current_plugin/ >> "$tempfile"
	done
	if [[ -s "$tempfile" ]]
	then echo -e "\n## NEEDS REVIEW: Offloaded Files" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Remote Images
	ag --path-to-ignore $0.ignore --php --skip-vcs-ignores -Q 'img src="http' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: External images" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Font Awesome
	ag --path-to-ignore $0.ignore --skip-vcs-ignores "kit.fontawesome." current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: Font Awesome (look for custom URL)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Core Has
	# Missing Checks for:
	# [ 'Class POP3', 'https://squirrelmail.org/' ],
	# [ 'PemFTP', 'https://www.phpclasses.org/packag --path-to-ignore $0.ignoree/1743-PHP-FTP-client-in-pure-PHP.html' ],
	# [ 'Redux', 'https://redux.js.org/' ],
	# [ 'The Incutio XML-RPC Library', 'http://scripts.incutio.com/xmlrpc/' ],
	# [ 'TinyMCE', 'https://www.tinymce.com/' ],
	# [ 'whatwg-fetch', 'https://github.com/github/fetch' ],

	for corefile in polyfill.js backbone.js clipboard.js clipboard.min.js closest.js codemirror.js jquery.color.js getid3.php FormData.js formdata.min.js jquery.hoverIntent* jquery.imgareaselect.* jquery.hotkeys.js jquery.ba-serializeobject.js iris* jquery.query-object.js jquery.suggest.js jquery.ui.touch-punch.min.js jquery.ui.touch-punch.js json2.js lodash.js masonry.js masonry.pkgd.min.js masonry.pkgd.js mediaelement-and-player.min.js moment.js moment.min.js pclzip.lib.php PasswordHash.php PHPMailer.php plupload.min.js plupload.full.min.js SimplePie.php thickbox.js twemoji.js twemoji.min.js underscore-min.js underscore.js zxcvbn.js plupload.full.js plupload.full.min.js moxie.js
	do
		find current_plugin -type f -name $corefile >> "$tempfile"
	done
	ag --path-to-ignore $0.ignore -G 'Requests.php' -Q 'Requests for PHP' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore -G 'random.php' -Q 'Random_* Compatibility Library' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php 'Horde_Text_Diff' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore -G '.js' 'benalman.com/projects/jquery-misc-plugins/' current_plugin/ >> "$tempfile"
	#ag --path-to-ignore $0.ignore -G '.js' 'license React' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: May be including files core has" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Sessions
	for sessions in ob_st session_
	do
		ag --path-to-ignore $0.ignore --skip-vcs-ignores --php $sessions current_plugin/ >> "$tempfile"
	done
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: php sessions can break caching, make sure it's encapsulated" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# wp-(conf|load|blog)
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php 'wp-(conf|load|blog)' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: direct calls to wp-(conf|load|blog) not allowed" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# POST|REQ|FILE|GET
	ag --path-to-ignore $0.ignore --skip-vcs-ignores '\$_(POST|REQ|SERVER|FILE|GET|COOK|SESS)' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: POST|REQ|FILE|GET must be sanitized/escaped" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Echo check
	ag --path-to-ignore $0.ignore --php -Q 'echo' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: Echoed variables have to be escaped" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Echo check
	ag --path-to-ignore $0.ignore --php -Q 'add_query_arg' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: add_query_arg has to be escaped when output" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# May be writing to files
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php "file_put_contents" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: May be writing to files" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# MPDF - https://mpdf.github.io/ -- https://github.com/mpdf/mpdf/releases
	ag -G 'mpdf.php' 'mPDF_VERSION' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: mPDF 8.1.0+ (16 April 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# elFinder - https://github.com/Studio-42/elFinder
	ag -G 'elfinder.min.js' ' Version = ' current_plugin/ >> "$tempfile"
	ag -G 'elfinder.version.js' 'elFinder.prototype.version' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: elFinder v2.1.61+ (26 July 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Freemius - https://github.com/Freemius/wordpress-sdk
	ag -G 'start.php' 'this_sdk_version = ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Freemius v2.4.5+ OR v2.5.3 (13 Dec 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Wisdom Plugin - https://wisdomplugin.com/support
	ag -G 'class-plugin-usage-tracker.php' -Q '* @version ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Wisdom Plugin v1.2.4+ (??)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# FPDF - http://www.fpdf.org
	ag -G 'fpdf.php' -Q 'FPDF_VERSION' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: FPDF v1.82+ (27 Aug 2020)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Chart.JS - https://github.com/chartjs/Chart.js
	ag --js -Q '* Chart.js' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Chart.js v3.8.2+ (26 July 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# ChartIst.JS - https://github.com/gionkunz/chartist-js/
	ag --js -Q '* Chartist.js ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Chartist.js v.11.4+ (13 September 2021) No updates in 3 years" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# FancyBox - https://github.com/fancyapps/fancybox
	ag --js '// fancyBox v' current_plugin/ >> "$tempfile"
	ag --js 'fancyBox - jQuery Plugin' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: FancyBox v1 OR v3, not v2 (cc3) OR v4 (commercial) -- current v3.5.7+ (27 Aug 2020)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Action scheduler - https://github.com/woocommerce/action-scheduler
	ag -G 'action-scheduler.php ' -Q "* Version:" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Action Scheduler v3.4.2+ (8 June 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Parsedown - https://github.com/erusev/parsedown
	ag -G 'parsedown.php ' -Q "const version" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Parsedown v1.7.4+ (30 Dec 2019)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# WP Session Manager - https://github.com/ericmann/wp-session-manager/
	ag -G 'wp-session-manager.php ' -Q "* Version:" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Action Scheduler v4.2.0+ (30 Mar 2019)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Option Tree
	ag -G 'ot-loader.php' -Q "define( 'OT_VERSION'" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Option Tree v2.7.3+ (18 May 2019)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# CMB2 - https://github.com/CMB2/CMB2
	ag -G 'init.php' 'const VERSION =' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: CMB2 v2.10.1+ (22 Feb 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# MetaBox - https://wordpress.org/plugins/meta-box/
	ag -G 'meta-box.php' 'Version:' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Meta Box v5.6.5+ (10 Jul 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# KIRKI - https://wordpress.org/plugins/kirki/
	ag -G 'kirki.php' ' Version: ' current_plugin/ >> "$tempfile"
	ag -G "settings.php" "define\( 'KIRKI_VERSION'" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Kirki v4.0.24+ (1 May 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# twilio-php-master - https://github.com/twilio/twilio-php // https://packagist.org/packages/twilio/sdk
	ag -G 'VersionInfo.php' ' const MAJOR =' current_plugin/ >> "$tempfile"
	ag -G 'VersionInfo.php' ' const MINOR =' current_plugin/ >> "$tempfile"
	ag -G 'VersionInfo.php' ' const PATCH =' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Twillo v6.40.0+ (21 July 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# TGM - https://github.com/TGMPA/TGM-Plugin-Activation
	ag -G 'class-tgm-plugin-activation.php' ' Version: ' current_plugin/ >> "$tempfile"
	ag -G 'class-tgm-plugin-activation.php' '@version ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: TGM v2.6.1+ (19 May 2016)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# ACF - https://wordpress.org/plugins/advanced-custom-fields/
	ag -G 'acf.php' 'Version: ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: ACF v6.0.5+ (21 November 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# PHP QR Code - http://phpqrcode.sourceforge.net
	ag -G 'phpqrcode.php' 'Version: ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: PHP QR Code v1.1.4+ (07 Oct 2010)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# SimpleDom - https://sourceforge.net/projects/simplehtmldom/files/
	ag -G 'simple_html_dom.php' 'ersion Rev. ' current_plugin/ >> "$tempfile"
	ag -G 'simple_html_dom.php' '@version ' current_plugin/ >> "$tempfile"
	ag -G 'simplehtmldom.php' 'ersion Rev. ' current_plugin/ >> "$tempfile"
	ag -G 'simplehtmldom.php' '@version ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: simple_html_dom v1.9.1 (291) (11 Nov 2019)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# DOMPDF - https://github.com/dompdf/dompdf
	find current_plugin -type f -name "Dompdf.php" >> "$tempfile"
	find current_plugin -type f -name "dompdf.php" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		> "$tempfile"
		echo -e "\n## VERSION CHECK: DOMPDF 2.0 (23 Jun 2022)" >> "$filename"
		find current_plugin -type f -name "VERSION" >> "$tempfile"
		find current_plugin -type f -name "VERSION" -exec cat '{}' ';' >> "$tempfile"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"
	find current_plugin -type f -name "VERSION" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: DOMPDF 2.0 (23 Jun 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Isotope - https://unpkg.com/isotope-layout@3.0.6/dist/isotope.pkgd.min.js
	ag -G 'isotope' 'Isotope PACKAGED' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Isotope v3.0.6+ (27 Aug 2020)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Nusoap - https://github.com/pwnlabs/nusoap
	ag -G 'nusoap.php' 'var $version = ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: NUsoap v0.9.12+ (26 April 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Redux - https://wordpress.org/plugins/redux-framework/
	ag -G 'class.redux-plugin.php' 'const VERSION = ' current_plugin/ >> "$tempfile"
	ag -G 'framework.php' 'public static \$_version =' current_plugin/ >> "$tempfile"
	ag -G 'framework.php' 'Redux_Core::\$version' current_plugin/ >> "$tempfile"
	ag -G 'redux-framework.php' 'Version:' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Redux v4.3.16+ (25 July 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Cherry - https://github.com/CherryFramework/cherry-framework
	ag -G 'cherry-core.php' ' Version:' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Cherry Framework v1.5.11+ (22 Nov 2021)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Mustach.php - https://github.com/bobthecow/mustache.php
	ag -G 'Engine.php' 'const VERSION' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Mustache.php v2.14.1 (20 Jan 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Bootstrap - https://github.com/twbs/bootstrap
	ag -G 'bootstrap.' 'Bootstrap v' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Bootstrap v5.2.1 (7 Sept 2022), v5.1.3 (9 Oct 2021), 4.6.2 (24 July 2022) " >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Bootstrap Date Picker - https://github.com/uxsolutions/bootstrap-datepicker
	ag -G 'bootstrap-datepicker' 'Datepicker for Bootstrap v' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Bootstrap Date Picker v1.9.0+ (20 May 2019)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Bootstrap Color Picker - https://github.com/itsjavi/bootstrap-colorpicker/
	ag -G 'bootstrap-colorpicker' 'Bootstrap Colorpicker v' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Bootstrap Color Picker v3.4.0+ (4 June 2021)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Codestar - https://github.com/Codestar/codestar-framework/
	ag -G 'framework.php' ' Version:' current_plugin/ >> "$tempfile"
	ag -G 'cs-framework.php' ' Version:' current_plugin/ >> "$tempfile"
	ag -G 'cs-framework-path.php' 'CS_VERSION' current_plugin/ >> "$tempfile"
	ag -G 'csf-config.php' ' Version:' current_plugin/ >> "$tempfile"
	ag -G 'codestar-framework.php' ' Version:' current_plugin/ >> "$tempfile"
	ag -G 'setup.class.php' 'public static \$version' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Codestar v2.2.8+ (13 Apr 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Carbon Fields - https://github.com/htmlburger/carbon-fields
	ag -G 'carbon-fields-plugin.php' -Q '* Version:' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Carbon Fields v3.3.4+ (5 May 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Winter MVC - https://github.com/sandiwinter/winter_mvc
	ag -G 'database.php' -Q ' * @version' current_plugin/ >> "$tempfile"
	ag -G 'init.php' -Q '$Winter_MVC_version_this' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Winter MVC 2.3 (9 June 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Adminer - https://www.adminer.org/
	ag -G 'adminer' -Q '@version ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Adminer v4.8.1+ (14 May 2021)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# SimpleXLS - https://github.com/shuchkin/simplexlsx
	ag -G 'simplexlsx.class.php' -Q ' * @version' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: SimpleXLSX php class v1.0.16+ (1 Jan 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# MediaElement - http://mediaelementjs.com/
	ag -G 'mediaelement.js' -Q 'mejs.version =' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: mediaelementjs v5.0.5+ (1 Jan 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# CKEditor - https://github.com/ckeditor/ckeditor5
	ag -W 10 -G 'ckeditor.js' -Q 'version:"' current_plugin/ >> "$tempfile" 
	ag -W 10 -G 'ckeditor.js' -Q 'CKEDITOR_VERSION="' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: CKEditor v34.2.0 (28 June 2022)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Tiny MCE - https://www.tiny.cloud/get-tiny/self-hosted/
	ag -G 'tinymce.min.js' -Q 'Version:' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: TinyMCE v6.1.x (1 July 2022) -- No plans for core to update to 5 - https://core.trac.wordpress.org/ticket/47218" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Swipebox - https://github.com/brutaldesign/swipebox
	find current_plugin -type f -iname "jquery.swipebox.min.js" >> "$tempfile"
	find current_plugin -type f -iname "jquery.swipebox.js" >> "$tempfile"
	ag --js "Swipebox" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Swipebox 1.5.2 (22 Jan 2021)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Moment.JS - https://momentjs.com/
	ag -W 10 -G 'moment.js' -Q 'version:"' current_plugin/ >> "$tempfile" 
	ag -W 10 -G 'moment.min.js' -Q '//! version : ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## VERSION CHECK: Moment.JS 2.29.3 (5 May 2022) -- also it's included in core" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# SweetAlert remote-data calls
	ag --width 100 "leave-russia-now-and-apply-your-skills-to-the-world" current_plugin/ >> "$tempfile"
	ag --width 100 "fWClXZd9c78" current_plugin/ >> "$tempfile"
	ag --width 100 "noWarMessageForRussians" current_plugin/ >> "$tempfile"
	ag --width 100 "flag-gimn" current_plugin/ >> "$tempfile"
	find current_plugin -type f -iname "sweetalert.js" >> "$tempfile"
	find current_plugin -type f -iname "sweetalert2.min.js" >> "$tempfile"
	find current_plugin -type f -iname "sweetalert2.all.js" >> "$tempfile"
	find current_plugin -type f -iname "sweetalert.min.js" >> "$tempfile"
	find current_plugin -type f -iname "sweetalert2.js" >> "$tempfile"
	find current_plugin -type f -iname "sweetalert.css" >> "$tempfile"
	find current_plugin -type f -iname "sweetalert.css" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: SweetAlert versions that make remote data calls are not allowed" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	## BEGIN GPL/LICENSING SECTION

	# CreativeCommons
	ag --width 100 --path-to-ignore $0.ignore --skip-vcs-ignores "creativecommons" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: CC is often non GPL (0 and 4.0 BY is okay)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# RelativePath.php - https://www.phpclasses.org/package/6844-PHP-Clean-file-name-paths-removing-redundant-elements.html
	find current_plugin -type f -iname "RelativePath.php" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NON-GPL: RelativePath requires attribution for Commerical Use." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Authorize.Net
	ag -G 'composer.json' 'authorizenet/authorizenet' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NON-GPL: Authorize.Net" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# LightningChart
	ag --php 'lightningchart' current_plugin/ >> "$tempfile"
	ag --js 'arction/lcjs' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NON-GPL: LightningChart (requires commerical use payments)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# amcharts
	ag --js 'amcharts.com' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NON-GPL: amcharts.com (cannot remove branding)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Greensock
	ag --js 'greensock.com' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NON-GPL: greensock.com" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# MixItUp
	ag --js 'kunkalabs.com/mixitup' current_plugin/ >> "$tempfile"
	ag --js 'MixItUp' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NON-GPL: MixItUp (v2 is allowed, v3 is not per their FAQ on https://www.kunkalabs.com/mixitup/licenses/ )" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Highcharts
	ag --js 'Highcharts' current_plugin/ >> "$tempfile"
	ag --php 'code.highcharts.com' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NON-GPL: Highcharts" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Magnificent - http://dimsemenov.com/plugins/magnific-popup/
	find current_plugin -type f -iname "magnific-popup.min.js" >> "$tempfile"
	find current_plugin -type f -iname "magnific-popup.js" >> "$tempfile"
	ag --js "magnific-popup" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## SECURITY: Magnificent Popups is abanoned (2016) and cannot be used." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# TimThumb
	ag --php "TimThumb by " current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## SECURITY: TimThumb not allowed (insecure/abandoned)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# MVC - https://github.com/tombenner/wp-mvc
	ag -G 'MvcLoader.php' 'Version:' current_plugin/ >> "$tempfile"
	ag -G 'wp_mvc.php' 'Version:' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## Security: MVC2 is not being maintained/supported, has security issues" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# WordPress Settings API - https://github.com/tareq1988/wordpress-settings-api-class
	ag --php "WordPress Settings API" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## SECURITY: Tareq WordPress Settings API not allowed (abandoned)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# WordPress Settings API - https://github.com/harishdasari/WP-Settings-API-Wrapper-Class
	ag --php "http://github.com/harishdasari" current_plugin/ >> "$tempfile"
	find current_plugin -type f -iname "class-hd-html-helper.php" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## SECURITY: HD WordPress Settings API not allowed (abandoned 8+ Years)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Zebra Form
	find current_plugin -type f -iname "Zebra_Form.php" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## SECURITY: Zebra Form is not updated in years and has an XSS issue" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# CSS Tidy
	ag --php "CSSTidy" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## SECURITY: CSSTidy not allowed (abandoned and alt version included in WP)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# VAFPress
	ag --php "vafpress-framework" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## SECURITY: VAFPress Framework not allowed (insecure and abandoned)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Titan Framework - https://wordpress.org/plugins/titan-framework/
	ag -G 'titan-framework.php' -Q 'Version:' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## SECURITY: Titan Framework no longer allowed (abandoned)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# ZeroClipboard - https://github.com/zeroclipboard/ZeroClipboard
	ag -G 'ZeroClipboard' -Q '* v' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## Security: ZeroClipboard is no longer supported, recommend clipboard.js" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# RelativePath Examples - have XSS
	find current_plugin -type f -name "RelativePath.Example1.php" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## SECURITY: Relative Path example file found (XSS)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# check_ajax_referer()
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php "check_ajax_referer" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: Check check_ajax_referer() third argument. If FALSE, needs a DIE." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# People use is_admin incorrectly
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php "is_admin" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: Make sure is_admin is used properly." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Make sure nonce logic is sane
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php "_nonce" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## NEEDS REVIEW: Make sure nonce logic is sane." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# error_reporting
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php "error_reporting" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php "WP_DEBUG" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php "display_errors" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## BAD PRACTICE: error_reporting" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# date_default_timezone_set
	ag --path-to-ignore $0.ignore --skip-vcs-ignores 'date_default_timezone_set' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## BAD PRACTICE: date_default_timezone_set" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# date_default_timezone_set
	ag --path-to-ignore $0.ignore --skip-vcs-ignores 'setlocale' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## BAD PRACTICE: setlocale MUST be set back to C" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Enqueues
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php -Q "<script src" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php -Q "<script def" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php -Q "<script type=" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php -Q "<link" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## BAD PRACTICE: Not using enqueues" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Hard Coded
	ag --path-to-ignore $0.ignore --skip-vcs-ignores -Q 'plugins_url' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores -Q 'WP_PLUGIN_URL' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores -Q 'WP_PLUGIN_DIR' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores -Q 'wp-content' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## BAD PRACTICE: Hard Coded paths (make sure plugins_url is used right)" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# HereDoc
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php -Q '<<<' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## BAD PRACTICE: HERE/NOWDOC can cause linting to miss things" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# PHP Short Tags
	ag --path-to-ignore $0.ignore --skip-vcs-ignores --php -Q '<?=' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## BAD PRACTICE: PHP Short Tags" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Vendor Directory
	find current_plugin -type d -name "vendor" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## WARNING: Vendor Folder found" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	## It would be very cool to check for all out of date libraries/code using MITRE or something.

	## COMPOSER
	find current_plugin -maxdepth 1 -type f -name "composer.json" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		composer outdated -d current_plugin > "$tempfile"
		echo -e "\n## COMPOSER OUTDATED CHECK" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	## NPM
	find current_plugin -maxdepth 1 -type f -name "package.json" >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		npm --prefix current_plugin outdated > "$tempfile"
		echo -e "\n## NPM OUTDATE CHECK" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	## Get includes and requires to look for file paths.
	ag --path-to-ignore $0.ignore --php -Q 'require_once' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q 'include_once' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q "require '" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q 'require "' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q "include '" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q 'include "' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## INCLUSION SCAN: If they use variables, check for file-path risks." >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	# Prefixes
	ag --path-to-ignore $0.ignore --skip-vcs-ignores "'PLUGIN_VERSION" current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --skip-vcs-ignores "'PLUGIN_DIR_PATH" current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## BAD PRACTICE: commonly used generic terms" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	## Get a list of all defines, functions, and classes.
	ag --path-to-ignore $0.ignore --php -Q 'define(' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q 'define (' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q 'function ' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q 'class ' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q 'Namespace ' current_plugin/ >> "$tempfile"
	ag --path-to-ignore $0.ignore --php -Q 'namespace ' current_plugin/ >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		echo -e "\n## PREFIX SCAN" >> "$filename"
		paste "$tempfile" >> "$filename"
	fi
	> "$tempfile"

	## PHPCS
	php phpcs -ns --extensions=php --standard=$0.xml --ignore-annotations current_plugin >> "$tempfile"
	if [[ -s "$tempfile" ]]
	then
		touch $phpcsfile
		paste "$tempfile" >> "$phpcsfile"

		## Clean up results! (NB: this is on a mac so -i needs a blank '' in front, thanks FreeBSD)
		sed -i '' 's/current_plugin\///g' "$phpcsfile"
		sed -i '' 's/\/Users\/ipstenu\/Downloads\///g' "$phpcsfile"
		sed -i '' 's/\/ipstenu\///g' "$phpcsfile"
		sed -i '' 's/?>//g' "$phpcsfile"
		sed -i '' 's/---------------------------------------------------------------------/\n/g' "$phpcsfile"

		echo -e "\n## PHPCS FILE CREATED" >> "$filename"

	fi
	> "$tempfile"

fi

## Clean up results! (NB: this is on a mac so -i needs a blank '' in front, thanks FreeBSD)
sed -i '' 's/current_plugin\///g' "$filename"
sed -i '' 's/?>//g' "$filename"

## All done
rm -rf current_plugin
rm "$tempfile"

echo -e "\nCompleted -- $(date)" >> "$filename"
echo -e "COMPLETE!"

## Open PHPCS
if [[ -s $phpcsfile ]]
then 
	bbedit "$phpcsfile"
fi

## Open the report
bbedit "$filename"

## Open the zip. We still want to check for false poz.
bbedit "$zip"
