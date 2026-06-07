# CGI interface notes

The CGI interface is planned as a second front end over the same simulator core.
It should not replace the terminal craft shell.

## Direction

The web interface should feel like a 1990s internal web gateway to a craft
terminal:

* plain CGI;
* fixed-width terminal output;
* HTML forms;
* `<pre>` blocks for command output;
* minimal CSS;
* no modern application framework;
* no heavy JavaScript;
* simple session files;
* shared simulator state and command dispatch.

## Proposed layout

    cgi-bin/5ess.cgi
    htdocs/5ess.css
    templates/
    lib/FiveESS/CGI.pm

## Required safety rules

* Escape all HTML output.
* Do not pass user input to shell commands.
* Validate session ids.
* Store session files under the configured state directory.
* Document web-server write permissions.
* Keep the simulator clearly separate from real telecommunications systems.

## Installation sketch

Copy `cgi-bin/5ess.cgi` to a CGI-enabled web server directory and set an
explicit writable state directory for the web server user:

    SetEnv 5ESS_STATE_DIR /var/local/5ess-emu

This is a future target.  The first implementation should wait until command
parsing and state handling are easier to test outside `5ESS.pl`.
