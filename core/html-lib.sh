#!/bin/bash
# Generic HTML-escaping -- no renderer/schedule concepts, just string
# escaping. Split out so render-html.sh and render-events.sh (neither of
# which sources the other) can both use the identical escape logic
# without each keeping its own copy.

_html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}
