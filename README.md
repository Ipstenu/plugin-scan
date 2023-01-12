# Plugin Scan

An example of the plugin scanner

This was built on MacOS and uses the following apps/libraries:

* Bash v4
* wget
* [ag (aka The Silver Seacher)](https://github.com/ggreer/the_silver_searcher)
* composer
* npm
* [WPCS (phpcs)](https://github.com/WordPress/WordPress-Coding-Standards)
* [bbedit](http://www.barebones.com/products/bbedit/index.html)

This does not, cannot, scan for everything. What it does is provide an overview look into the code and outputs in a manner easy to return to a developer.

It requires a lot of manual review. Many things will be listed that are okay, but are often not. In addition, it lacks some automation (like auto-checking if a library is up to date) and checks for shortcodes.

The full 'official' version also has a list of recidivists, or people who were banned (generally for GPL violations, theft of code, or abusive behavior towards the community). They tend to like to make mulitple accounts. In the interest of personal security, that section has been omitted.

## Instructions

The code can be run via `./plugin-scan.sh [FILENAME.ZIP|HTTP://EXAMPLE.COM/URL/FILENAME.ZIP]`

It will return one or two files named from the zip, with details about anything found.
