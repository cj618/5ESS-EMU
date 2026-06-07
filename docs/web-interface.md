# Web interface notes

The web interface is planned as a second front end over the same simulator core.
It should not replace the terminal craft shell.

## Direction

The web interface should feel like a 1990s internal web gateway to a craft
terminal:

* plain Perl CGI;
* fixed-width terminal output;
* HTML forms;
* preformatted command output;
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

## Required rules

* Escape HTML output.
* Avoid shelling out from request parameters.
* Validate session ids.
* Store session files under the configured state directory.
* Document web-server write permissions.

This is a future target. The first implementation should wait until command
parsing and state handling are easier to test outside `5ESS.pl`.
