#!/usr/bin/env bash

# Log a message.
function log::msg {
	echo "[+] $1"
}

# Log a message at a sub-level.
function log::submsg {
	echo "   ⠿ $1"
}

# Log an error.
function log::err {
	echo "[x] $1" >&2
}

# Log an error at a sub-level.
function log::suberr {
	echo "   ⠍ $1" >&2
}
