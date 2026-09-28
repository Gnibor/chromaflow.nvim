#!/usr/bin/env bash
# ChromaFlow showcase: Bash syntax and Tree-sitter inspection surface.

local_value="plain"
readonly readonly_value="locked" # Shell keyword; no reliable Bash-LSP modifier assumed.
export DEMO_ENVIRONMENT="environment"
first_argument=${1:-fallback}

indexed=(zero one "two words")
declare -A mapped=([name]="demo" [count]=2)

show_values() {
	local parameter=$1
	local substituted
	substituted=$(printf '%s' "$parameter" | sed 's/demo/showcase/')
	local arithmetic=$(( ${mapped[count]} + 40 ))

	# Bash builtins: printf, local, readonly, export, test, read.
	printf '%s %s %s\n' "$substituted" "$arithmetic" "${DEMO_ENVIRONMENT:-missing}"

	if [[ -n "$parameter" && "$parameter" != "skip" ]]; then
		case "$parameter" in
			one|two) printf '%s\n' "matched" ;;
			*) printf '%s\n' "default" ;;
		esac
	fi

	for item in "${indexed[@]}"; do
		printf '[%s]\n' "$item"
	done

	while read -r line; do
		printf 'heredoc:%s\n' "$line"
	break
	done <<'DEMO_TEXT'
literal $variable and `command` text
DEMO_TEXT

	: > /dev/null
	printf '%s\n' "$readonly_value" "${BASH_VERSION}" "$?" "$$"
}

show_values "$first_argument"
