#!/usr/bin/env bash
# shjq: shell JSON query processor
#
# Credits: Tirito6626, 2026
# License: Apache License 2.0
#

### Format
## shelljq uses own array format for storing multi-dimensional objects in two-dimensional array (indexed arrays are not supported).
## 
## by default, root array is assumed to be an object, unless it contains `_shjq_arr` key and its value is 1, then the array is parsed as JSON array
## 
## bash array keys can represent:
## - integers, null and booleans, saved as literals
## ```bash
## [key]=1
## [key]=true
## [key]=null
## ```
## 
## - literal string, wrapped in double quotes by default
## ```bash
## [key]='"value"' # or 'value' if raw
## ```
## 
## - JSON objects and have prefix `@A ` in value (as in -A, associative) with top children keys in a list, separated with spaces
## ```bash
## # { "key": { "key1": "bar", "key2": "baz", "key3": { "foo": "bar" } } }
## [key]='@A key1 key2 key3'
## [key.key1]='"bar"'
## [key.key2]='"baz"'
## [key.key3]='@A foo'
## [key.key3.foo]='"bar"'
## ```
## 
## - JSON arrays and have prefix `@a ` in value (as in -a, indexed) with each element index, separated with spaces
## ```bash
## # { "key": [ "foo", "bar", "baz" ] }
## [key]='@a 0 1 2'
## [key.0]='"foo"'
## [key.1]='"bar"'
## [key.2]='"baz"'
## ```
## 
## `@A ` and `@a ` serve as markers for JSON objects/arrays and contains pointers to its children. if you manually remove one of the keys from `@A ...` or `@a ...`, it will be ignored by the parser and not added into the JSON
## 
## by design this format is made for convenient and simple JSON projection onto associative array without enforcing types or being strict

### Query
## follows similar to JQ(1)'s basic query syntax without the leading dot
## - key
## - key.subkey
## - arr[] -> return each element individually
## - arr[].key
## - arr[1,2].key
## - arr[-1,2].key -> -1 resolves to `arr`s last index
[[ "${_green}" ]] || {
_green=$'\e[38;5;2m'
_red=$'\e[38;5;1m'
_yellow=$'\e[30;93m'
_white=$'\e[38;5;255m'
_bold=$'\e[1m'
_gray=$'\e[38;5;240m'
_nc=$'\e[0m'
}
SHELLJQ_VERSION='v1.1.0-alpha'

shjq_docs="<docs placeholder>"
shjq_help="<help placeholder>"
# zsh-specific configuration
num_regex='\[(-?[0-9]+)\]'

### Functions

if [[ "$ZSH_VERSION" ]]; then
	is_zsh=1
	emulate ksh
	zmodload zsh/parameter
	setopt bash_rematch
	[[ $ZSH_EVAL_CONTEXT =~ :file$ ]] && sourced=1 || sourced=0
	__unset_parent() { parent[-1]=(); parent_t[-1]=(); }; 
	__unset_parent_index() { parent[-1]=(); parent_t[-1]=(); index[-1]=(); };
	bool_to_int() { is_true "${(P)1:-false}"; eval "$1=$(( ! $? ))"; }
	int_to_bool() case "${(P)1}" in 1|true) eval "$1=true" ;; *) eval "$1=false" ;; esac
else
	[[ "${BASH_VERSION[*]}" > "5 2 0" ]] && shopt -u patsub_replacement
	is_zsh=0
	shopt -s extglob
	(return 0 2>/dev/null) && sourced=1 || sourced=0
	__unset_parent() { unset 'parent[-1]' 'parent_t[-1]';  }; 
	__unset_parent_index() { unset 'parent[-1]' 'parent_t[-1]' 'index[-1]';  };
### bool_to_int <var>
## convert $var's value into 1 or 0
	bool_to_int() { is_true "${!1:-false}"; eval "$1=$(( ! $? ))"; }

### int_to_bool <var>
## convert $var's value into literal `true` or `false`
	int_to_bool() case "${!1}" in 1|true) eval "$1=true" ;; *) eval "$1=false" ;; esac
fi

read_until_v2() {
	local e line="$2" char='' delim lline="${#2}"
	for _ in _; do
		for (( e=0; e<lline; e++ )); do
    		char="${line:$e:1}"
			chars+="$char"
			case "$1" in *"$char"*) break 2 ;; *) [[ "$char" == '\' ]] && ((++e)) && chars+="${line:$e:1}" ;; esac
		done
		return 1
	done
	return 0
}

read_until() {
	local e='' line="$2" char='' delim lline="${#2}"
	for (( e=1; e<lline; e++ )); do
    	char="${line:$e:1}"
		case "$1" in *"$char"*) break ;; *) [[ "$char" == '\' ]] && ((e++)) ;; esac
	done
	chars="${line::$e}"
}
### is_true <value> -> $? (0 | 1)
## returns 0 or 1 depending on the $value (1/true => 0, 0/false => 1, * => 1)
is_true() case "$1" in
	true|1) return 0 ;;
	false|0) return 1 ;;
	*) return 1 ;;
esac
declare -fr is_true >/dev/null 2>&1

sanitize_string() {
	### sanitize_string <string> -> sanitized_string
	## sanitize $string to be a valid string value
	local string="$1"
	string="${string//\\/\\\\}"
	string="${string//\"/\\\"}"
	string="${string//\`/\\\`}"
	sanitized_string="\"$string\""
}

unwrap_string() {
	### unwrap_string <string> -> raw_string
	## unquote $string and remove backslashes
	local string="$1"
	string="${string#\"}"
	string="${string%\"}"
	raw_string="${string//\\}"
}

typecheck() {
	### typecheck <value> <type?> -> $? (0 | 1)
	## supported types:
	## 1/string, 2/int, 3/bool, 4/null, 5/object, 6/array
	## - if no `type` supplied, the value is checked with every type
	local value="$1" type="$2"
	#set +x
	case "$type" in
		1|string)
			#set -x
			local chars=''
			[[ "${value::1}" != '"' ]] && return 1
			value="${value:1}"
			read_until_v2 '"' "$value" || return 1
			(( "${#value}" == "${#chars}" )) || return 1
			return 0
			#set +x
			;;
		2|int)
			if (( ! is_zsh )); then
				LANG=C builtin printf "%f" "$value" >/dev/null 2>&1 || return 1
			else
				[[ "$value" == 0 ]] && return 0
				(( "$value" == 0 )) 2>/dev/null
				(( $? == 0 || $? == 2 )) && return 1
			fi
			;;
		3|bool) case "$value" in true|false) return 0 ;; *) return 1 ;; esac ;;
		4|null) [[ "$value" == null ]]; return ;;
		5|object)
			if [[ "${value::1}" == '{' ]] && json_trim "$value" true true; then
				return 0
			else
				return 1
			fi
			;;
		6|array)
			if [[ "${value::1}" == '[' ]] && json_trim "$value" true true; then
				return 0
			else
				return 1
			fi
			;;
		*)
			case "$value" in
				'"'*) typecheck "$value" 1; return ;;
          		true|false|null|''|-?[0-9]+) return 0 ;;
          		'{'*|'['*) json_trim "$value" true true; return ;;
				*)
					typecheck "$value" 2 || \
					return 1
			esac
	esac
	return 0
}

kv_to_object() {
	local __="${!1}"
	IFS=':' read key __ <<< "$__"
	key="\"${key//\"}\""
	case "${kv_type:-1}" in
		1) __="\"${__//\"/\\\"}\"" ;;
	esac
	__="{$key:$__}"
	eval "$1='$__'" 
}

error() {
  	is_true "${sub:-$2}" && __shjq_error="$1" || printf '%s\n' "error: $1" >&2
	return 0
}



json_trim() {
	### json_trim <input> <validate?> <sub?> -> json_trim_output
	## trim JSON
	## - if `validate` = true, the input is validated for structure and individual values (slower)
	## - if `sub` = true, output is only saved into `json_trim_output` instead of being printed
	#set +x
	#trap profiler DEBUG
	__typecheck() {
		if [[ "$value" ]] && ! typecheck "$value"; then
			local __=$(( ${#value} + 10))
			error "invalid key value \`$value\`"$'\n'"...${1:i-__:$__}..." "$sub"
			return 1
		fi
		value=''
		return 0
	}
	__inside_string() {
		newstring+='"'
		if ((is_value)); then
			value+='"'
			for (( i=i+1; i < len; i++ )); do
				char="${input:$i:1}"
				case "$char" in
					'\') char="\\${input:$i+1:1}"; ((i++)) ;;
					'"') ((dquotes++)); isvalue=0 value+="$char" inside_string=0; __typecheck || return; break ;; 
					$'\n') continue ;;
        		esac
		        value+="$char"
				newstring+="$char"
			done
		else
			for (( i=i+1; i < len; i++ )); do
				char="${input:$i:1}"
				case "$char" in '\') char="\\${input:$i+1:1}"; ((i++)) ;; '"') ((dquotes++)); inside_string=0; break ;; $'\n') continue ;; esac
		        	newstring+="$char"
				done
		fi
	}
	__missing_comma() {
		error "expected comma at :$i"$'\n'"$newstring${_red},${_nc}${char}"
		return 1
	}
  	local inside_string=0
	local input="$1"
  	json_trim_output=""
	local len="${#1}"
  	local validate="${2:-false}"
 	local sub="${3:-false}"
  	local escaped=0
	local code=0
  	local i=0
  	if ! is_true "${validate}"; then
		for (( i=0; i<len; i++ )); do
			char="${input:$i:1}"
			case "$char" in
				'\') char="\\${input:$i+1:1}"; ((i++)) ;;
				'"') ((inside_string ^= 1)) ;;
				' ')  (( ! inside_string )) && continue ;;
				$'\n') continue ;;
        	esac
		    json_trim_output+="$char"
	    done
  	else
		if (( len < 3 )); then
			case "$input" in
				'{}'|'[]') json_trim_output="$input"; return 0 ;;
				*) error "invalid JSON: $input"; return 1 ;;
			esac
		fi
    	local newstring=''  newstring='' value='' firstchar='' quoted=false prevchar='' unquotedchars=''
		local isvalue=0 colons=0 colons_needed=0 depth=1 dquotes=0 bdepth=0 commas=0 inside_string=0 code=0 spaces=0
		char="${input::1}"
		prevchar="$char"
		newstring+="$char"
	   #set -x
		for (( i=1; i < len; i++ )); do
			char="${input:$i:1}"
            case "$char" in
                '"') ((++dquotes)); [[ '{[,:' != *"$prevchar"* ]] && __missing_comma; __inside_string ;;
                ':') ((++colons)); isvalue=1 ;;
                '{') ((++depth)); isvalue=0; [[ '"[,:' != *"$prevchar"* ]] && __missing_comma ;;
                '}') __typecheck || return; ((--depth)) ;;
                '[') isvalue=1; ((++bdepth)); [[ '"[,:' != *"$prevchar"* ]] && __missing_comma ;;
                ']') __typecheck || return; ((--bdepth)) ;;
				$'\n'|' ') continue ;;
		        ',')
					[[ "$prevchar" == ',' ]] && error "unexpected ',,'"$'\n'"${result::-1}${_red},${_nc}${char}" "$sub" && return 1
					__typecheck || return; 
					isvalue=0
					;;
                *) (( isvalue )) && value+="$char" ;;
            esac
        	prevchar="$char"
      		newstring+="$char"
    	done 

		if (( dquotes % 2 )); then
      		if (( depth > 0 )); then 
        		error 'expected `"` but got EOF instead' "$sub"
        		code=1
        		return 1
      		else 
        		error "missing $missingq \`\"\`" "$sub"
	    	    code=1
	      	fi
		else
			[[ "${newstring::1}" != '[' ]] && (( colons == 0 )) && error "at least one key and value required" && code=1
		fi
		if (( depth+bdepth != 0 )); then
    		(( depth > 0 )) && error "missing ${depth} \`}\`" 
    		(( depth < 0 )) && error "missing ${depth//\-} \`$firstchar\`"
	    	(( bdepth > 0 )) && error "missing ${bdepth} \`]\`"
    		(( bdepth < 0 )) && error "missing ${bdepth//-} \`[\`"
			code=1
		fi
    	[ ! -z "${unquotedchars//\\n}" ] && error "unquoted characters: $unquotedchars" && code=1
			json_trim_output="$newstring"
  	fi
  	! is_true "${sub:-false}" && echo "$json_trim_output"
  	return "${code}"
}

nested=0

parse_object() {
	### parse_object <key name(s)> <parent_key> -> parsed_object
	## build JSON object from its keys
	##
	## - if `$shjq_arr` variable is set, its value is used as input array
	if [[ "$shjq_arr" && "$shjq_arr" != json_to_arr_array ]]; then
		declare -p "$shjq_arr" >/dev/null 2>&1 || { error "invalid or empty array"; return 1; }
		(( ! is_zsh )) && declare -n json_to_arr_array="$shjq_arr" || typeset -gA json_to_arr_array=("${(kv)${(P)shjq_arr}[@]}");
	fi
    local data=''
	local keys=($1) key
    [[ "$2" ]] && local parent="$2."
    [[ "$3" ]] && local pretty=true && local space="$4" || local pretty=false
	IFS=$' \t\n'
	for key in "${keys[@]}"; do
		local value="${json_to_arr_array[${parent}${key}]}"
        case "${value::3}" in
			'@a ') parse_array "${value//@a }" "${parent}${key}"; value="$parsed_array" ;;
			'@A ') parse_object "${value//@A }" "${parent}${key}"; value="$parsed_object" ;;
		esac
		value="${value%% }"
		if ! typecheck "$value"; then 
			sanitize_string "$value"; 
			value="$sanitized_string"
		fi
		data+=",\"${key}\":${value%% }"
	done
	parsed_object="{${data##,}}"
}

parse_array() {
	### parse_array <key(s)> <parent_key?> -> parsed_array
	## build JSON array from key names
	##
	## - if `$shjq_arr` variable is set, its value is used as input array
	if [[ "$shjq_arr" && "$shjq_arr" != json_to_arr_array ]]; then
		declare -p "$shjq_arr" >/dev/null 2>&1 || { error "invalid or empty array"; return 1; }
		(( ! is_zsh )) && declare -n json_to_arr_array="$shjq_arr" || typeset -gA json_to_arr_array=("${(kv)${(P)shjq_arr}[@]}");
	fi
    local data=''
    [[ "$2" ]] && local parent="$2."
    IFS=$' \t\n'
    local keys=($1) key
	for key in "${keys[@]}"; do
        [[ "$key" == *'.'* ]] && continue
    	local value="${json_to_arr_array[${parent}$key]}"
        case "${value::3}" in
			'@a ') parse_array "${value//@a }" "${parent}${key}"; value="$parsed_array" ;;
			'@A ') parse_object "${value//@A }" "${parent}${key}"; value="$parsed_object" ;;
		esac
		value="${value%% }"
		if ! typecheck "$value"; then 
			sanitize_string "$value"; 
			value="$sanitized_string"
		fi
		data+=",${value}"
	done
	data="${data%%\,}"
    parsed_array="[${data##,}]"
}

arr_to_json() {
	### arr_to_json <arr_name> <sub?> -> arr_to_json_output
	## convert associative array into JSON
	## - if `sub` = true, output is only saved into `arr_to_json_output` instead of being printed
	json_to_json_output=''
  	local data=''
	local arrname="$1"
  	local sub="${2:-false}"
	local keys=() key=''
	if (( is_zsh )); then
		[[ "$arrname" != json_to_arr_array ]] && typeset -gA json_to_arr_array=("${(kv)${(P)arrname}[@]}")
		for key in "${(k)json_to_arr_array[@]}"; do
			[[ "$key" == *\.*  || "$key" == "_shjq_arr" ]] && continue
			keys+=("$key")
		done
		[[ "${#keys[@]}" == 0 ]] && echo "empty array" && return 1
	else
		[[ "$arrname" != json_to_arr_array ]] && declare -n json_to_arr_array="$arrname"
		for key in "${!json_to_arr_array[@]}"; do
			[[ "$key" == *\.* || "$key" == "_shjq_arr" ]] && continue
			keys+=("$key")
		done
		[[ "${#keys[@]}" == 0 ]] && echo "empty array" && return 1
	fi
	#set -x
	if [[ "${json_to_arr_array[_shjq_arr]}" == 1 ]]; then
		local len="${#keys[@]}" _keys=''
		eval "printf -v _keys '%s ' {0..$len}"
		#unset json_to_arr_array[_shjq_arr]
		parse_array "${_keys}"
		arr_to_json_output="$parsed_array"
	else
    	parse_object "${keys[*]}"
		arr_to_json_output="$parsed_object"
	fi
  	is_true "$sub" || echo "$arr_to_json_output"
  	return 0
}

json_pretty() {
	### json_pretty <input> <sub?> -> json_pretty_output
	## returns JSON input with highlight and indentation (pretty-print)
	## - if `sub` = true, output is only saved into `json_pretty_output` instead of being printed
	local input="$1"
	local sub="${2:-false}"
	local indent="${3:-  }"
  	json_pretty_output=""
  	local depth=0 newstring='' firstchar='' iskey=1 escaped=0 brackets=0 space='' char1='' i=0
  	local IFS=$'\n'
  	for line in "$input"; do
		[[ "${1::1}" == '"' ]] && ((iskey ^= 1))
		local lline="${#line}"
        for (( i=0; i<lline; i++ )); do
    		char=${line:$i:1}
            (( escaped )) && newstring+="$char" && escaped=0 && continue
            case "$char" in
				' '|$'\n') continue ;; 
              	',') newstring+=$',\n'"$space"; iskey=1 ;;
              	'"')
					chars=''
					read_until '"' "${line:$i}"
					(( i=i+${#chars} ))
					((iskey == 0 || brackets == 1)) && newstring+="${_green}${chars}\"${_nc}" || newstring+="${_nc}${chars}\"${_nc}"
					;;
                '\') escaped=1 ;;
                ':') iskey=0; newstring+=': ' ;;
                '{') 
					((brackets == 1)) && brackets=2; # set to 2 if it's inside []
					iskey=1
					space+='  '
					newstring+="$char"$'\n'"$space"
					;;
				'}') 
					#((brackets == 2)) && brackets=1 # check if it's inside array and set highlight to prevent resetting string color
					space=${space:: -2} && newstring+=$'\n'"${space}$char" 
					;;
				'[') brackets=1; iskey=0; space+='  ' && newstring+="$char"$'\n'"$space" ;;
                ']') 
					brackets=0
					local _a="["$'\n'"$space"
					if [[ "${newstring: -${#_a}}" == "$_a" ]]; then 
						newstring="${newstring:: -${#_a}}[]" 
						space=${space:: -2}
					else
						space=${space:: -2}
						newstring+=$'\n'"${space}$char"
					fi
					;;
				't'|'f'|'n') 
					if is_true "${line:$i:4}"; then
						newstring+=$'\e[38;2;84;150;210m'"true${_nc}"
						(( i=i+3 ))
					elif [[ "${line:$i:5}" == 'false' ]]; then
						newstring+=$'\e[38;2;84;150;210m'"false${_nc}"
						(( i=i+4 ))
					elif [[ "${line:$i:4}" == 'null' ]]; then
						newstring+="${_gray}null${_nc}" 
						(( i=i+3 ))
					else
						read_until ',/{}[]' "${line:$i}"
						error "invalid key value: ${chars}"
						local _trash="${line:$i-5:$i+${#chars}}"
						echo "${_trash/$chars/${_red}$chars${_nc}}"
						return 1
					fi
					;;
				*)
					# highlight all other types with yellow, delimeter is bracket or comma
					#((++i))
					read_until ',/{}[]' "${line:$i}"
					typecheck "$chars" int || { 
						error "invalid key value: ${chars}"
						local _trash="${line:$i-5:$i+${#chars}}"
						echo "${_trash/$chars/${_red}$chars${_nc}}"
						return 1
					}
					newstring+="${_yellow}${chars}${_nc}"
					(( i=i+${#chars}-1 ))
            	esac
          	done
    	newstring+=$'\n'
  done
  json_pretty_output="${newstring}"
  is_true "${sub:-false}" || echo "${json_pretty_output%%$'\n'}"
  return 0
}

function profiler {
	### profiler
	## used inside bash DEBUG trap, returns the execution time of each operation/command in μs
	snap="${EPOCHREALTIME//./}"
	#snap="${snap::-3}"
	printf "\e[1F%s μs\e[1E        %s\n" "$((snap - snap1))" "$BASH_COMMAND"
	snap1="$snap"
}

key_to_arr() {
	### key_to_arr <key> <arr_name?> <raw?> -> json_to_arr_array[] | <arr_name>[]
	## build a new array from a key object/array
	## - if `arr_name` is supplied, its value is used as output array
	## - `raw` is passed to `json_to_arr`
	##
	## - if `$shjq_arr` variable is set, its value is used as input array
	#set -x
	local query="$1" arrname="$2" raw="${3:-false}"

	if [[ "$shjq_arr" && "$shjq_arr" != json_to_arr_array ]]; then
		declare -p "$shjq_arr" >/dev/null 2>&1 || { error "invalid or empty array"; return 1; }
		(( ! is_zsh )) && declare -n json_to_arr_array="$shjq_arr" || typeset -gA json_to_arr_array=("${(kv)${(P)shjq_arr}[@]}");
	fi

	[[ -z "${json_to_arr_array[*]}" ]] && error "invalid or empty array" && return 1

	_parse_query
	key="$query"
	local keys="${json_to_arr_array[$key]:2}"
	
	case "${json_to_arr_array[$key]::2}" in
		'@a')
			parse_array "$keys" "$key"
			parsed_array="${parsed_array//\"$key1\":}"
			json_to_arr "${parsed_array}" "$arrname" "$raw"
			;;
		'@A')
			parse_object "$keys" "$key"
			parsed_object="${parsed_object//\"$key1\":}"
			json_to_arr "${parsed_object}" "$arrname" "$raw"
			;;
		'') error "cannot convert non-object or array to array"; return 1 ;;
	esac

}

json_to_arr() {
	#trap profiler DEBUG
	### json_to_arr <input> <arr_name?> <raw?> -> json_to_arr_array[] | <arr_name>[] | json_to_arr_output
	## - if `arr_name` is supplied, it's used as array reference (default is json_to_arr_array)
	##   - if `arr_name` is not a valid array, a new one is created instead
	## - if `raw` = true, all key string values are saved without the quoting
		
	[[ -z "${1::1}" ]] && error "no input provided" && return 1
	[[ '{[' == *"${1::1}"* ]] || { error "expected '{' or '[', got '${json::1}' instead"; return 1; }

	_parse_string() {
		chars=''
		((++i))
		line="${json_keys[i]}"
		[[ '[]{}' != *"${value: -1}"* ]] && chars+=','
		until read_until_v2 '"' "$line"; do
			((++i))
			line="${json_keys[i]}"
			[[ '[]{}' != *"${chars: -1}"* && '[]{}' != *"${line::1}"* ]] && chars+=','
		done
	}
	json_to_arr_output=''
  	local ifs="$IFS"
  	local IFS="."
	local json="$1" arrname="$2" raw="${3:-false}"
	local i line is_array=0 append_key key value depth result curr_index raw_value chars=''
  	local json_keys=() index=()

	if [[ "${pre_parent}" ]]; then
		local parent=("${pre_parent[@]}") parent_t=("${pre_parent_t[@]}")
		unset pre_parent pre_parent_t
	else
		local parent=() parent_t=()
		if [[ "${json::1}" == '[' ]]; then 
			json_to_arr_array[_shjq_arr]=1
			is_array=1
		fi
	fi

	if [[ "${json::1}" == '[' ]]; then 
		index=(0)
		json="${json#\[}"
		json=",${json}"
		json="${json%\]}"
	else
		json="${json#\{}"
		json="${json%\}}"
	fi

	if (( is_zsh )); then
		declare -p json_to_arr_array >/dev/null 2>&1 || typeset -gA json_to_arr_array=()
	elif [[ "${arrname}" ]]; then
		declare -p "$arrname" >/dev/null 2>&1 || declare -gA "$arrname"
		declare -n json_to_arr_array="$arrname"
	else
		declare -gA json_to_arr_array=()
	fi


	json="${json//\\/\\\\}"
	json="${json//\{\}/%BRACES%}"
	json="${json//\{/{,}"
	json="${json//\}/,\}}"
  	json="${json//\[\]/%BRACKETS%}"
  	json="${json//\[/[,}"
	json="${json//\]/,]}"
	json="${json## }"
	json="${json%% }"
	json="${json//\" :/\":}"
	#json="${json:1:-1}"
	if (( is_zsh )); then 
		IFS=',' read -r -A json_keys <<< "$json"
	else 
		IFS=',' read -r -a json_keys <<< "${json:1}"
	fi
	#unset IFS
	arr_len="${#json_keys[@]}"
	#set +x
	for ((i=0; i<=arr_len; i++)); do
	# line in "${json_keys[@]}"; do
		line="${json_keys[i]}"
		[[ "${line::1}" ]] || continue

        IFS=':' read key value <<< "${line//: /:}"
		#echo "$key $value"
		[[ "${key::1}" || "$key" == '_shjq_arr' ]] || continue
		key="${key# }"
		key="${key%% }"
		parent_prefix="${prefix:+$prefix.}${parent[*]:+${parent[*]}.}"
		#echo "$key $value $parent_prefix ${index[@]}"
		#echo "$key $value"
		if [ -z "$value" ]; then
			[[ ${#index[@]} > 0 ]] && curr_index="${index[-1]}"
			if [[ ${#parent[@]} > 0 ]]; then
				case "$key" in
				']') __unset_parent_index ;;
                '{')
					json_to_arr_array[${parent_prefix%%\.}]+=" ${curr_index}"
					parent+=("${curr_index}")
					parent_t+=("{")
                    json_to_arr_array[${parent_prefix}${curr_index}]="@A"
					;;
				'}')
                    __unset_parent;
					[[ "${#parent_t[@]}" > 0 && "${parent_t[-1]}" == '[' || "$is_array" == 1 ]] && ((++index[-1]))
					;;
				*)
					if [[ "${key::1}" == '"' ]] && [[ "${key: -1}" != '"' || "${key: -2}" == '\"' ]]; then
						value="$key"; _parse_string; key+="$chars"
					fi
					is_true "$raw" && unwrap_string "$key" && key="$raw_string"
					json_to_arr_array[${parent_prefix}${curr_index}]="$key"
                    json_to_arr_array[${parent_prefix%%\.}]+=" ${curr_index}"
                   	[[ "${parent_t[-1]}" == '[' ]] && ((++index[-1]))
				esac
            elif [[ "$key" == '{' ]]; then
					parent+=("${index[-1]}")
					parent_t+=("{")
					json_to_arr_array[${parent_prefix}${curr_index}]="@A"
			else
                if (( is_array )); then
					if [[ "${key::1}" == '"' ]] && [[ "${key: -1}" != '"' || "${key: -2}" == '\"' ]]; then
						value="$key"; _parse_string; key+="$chars"
					fi
					is_true "$raw" && unwrap_string "$key" && key="$raw_string"
					json_to_arr_array[${parent_prefix}${curr_index}]="$key"
					((++index[-1]))
				fi
            fi
			
        else
			#echo "$value"
			value="${value# }"
			value="${value% }"
            key="${key//\"}"
            case "$value" in
                '{}'|'[]')  json_to_arr_array[${parent_prefix}${key}]="$value" ;;
                '{')
					json_to_arr_array[${parent_prefix}${key}]="@A"
					[[ ${#parent[@]} > 0 ]] && json_to_arr_array[${parent_prefix%%\.}]+=" $key"
                    parent+=("$key")
					parent_t+=('{')
					;;
				'[')
					[[ ${#parent[@]} > 0 ]] && json_to_arr_array[${parent_prefix%%\.}]+=" $key"
                    parent+=("$key")
					parent_t+=('[')
					json_to_arr_array[${parent_prefix}${key}]="@a" 
					index+=(0)
                    ;;
                *)
					case "$value" in
						'%BRACKETS%') value='[]' ;;
						'%BRACES%') value='{}'	;;
						*) 
							if [[ "${value::1}" == '"' ]] && [[ "${value: -1}" != '"' || "${value: -2}" == '\"' ]]; then
								_parse_string; value+="$chars"
							fi
							is_true "$raw" && unwrap_string "$value" && value="$raw_string" 
						;;
					esac
					[[ ${#parent[@]} > 0 ]] && json_to_arr_array[${parent_prefix%%\.}]+=" $key"
					json_to_arr_array[${parent_prefix}${key}]="$value"
            esac
        fi
    done
	unset IFS
    IFS="$ifs"

	if (( is_zsh )) && [[ "$arrname" ]]; then
		eval "typeset -gA ${arrname}=(\"\${(kv)json_to_arr_array[@]}\")"
	fi
	return 0
}

_parse_query() {
	while [[ "$query" =~ $num_regex ]]; do
		local captured="${BASH_REMATCH[1]}"
		if [[ "$captured" == -1 ]]; then
			local parent="${query/\[-1\]*}"
			local captured1="${json_to_arr_array[${parent}]##* }"
		fi
		query="${query/\[$captured\]/.${captured1:-$captured}}"
	done
	query="${query//../.}"
	query="${query##.}"
}

json_query() {
	### json_query <query(s)> <raw?> <sub?> -> json_query_output[]
	## perform JSON query
	## if $raw = true, double quotes are removed from the output (if the output is a string)
	## if $sub = true, $input is omitted, otherwise $input is used as JSON input and converted into array
	##
	## - if `$shjq_arr` variable is set, its value is used as input array
	json_query_output=()
  	local raw="${2:-false}"
  	local sub="${3:-false}"
  	local result captured1 fullkey=''
	local queries=(${1})

	if [[ "$shjq_arr" && "$shjq_arr" != json_to_arr_array ]]; then
		declare -p "$shjq_arr" >/dev/null 2>&1 || { error "invalid or empty array"; return 1; }
		(( ! is_zsh )) && declare -n json_to_arr_array="$shjq_arr" || typeset -gA json_to_arr_array=("${(kv)${(P)shjq_arr}[@]}");
	fi

	[[ -z "${json_to_arr_array[*]}" ]] && error "invalid or empty array" && return 1
	#json_trim "$json"
    if [[ -z "$queries" ]]; then
		result="${input:-$4}"
	else
		for query in "${queries[@]}"; do
			_parse_query
			local parent="${query%\.*}"
			local key="${query##${parent}.}" 
			# match key[] or key[<i>,<i>, ...]
			if [[ "$query" == *'[]'* || "$query" == *","* ]]; then
				multi_output=1
				local subkey='' query_arr=() subkeys_arr=() i=-1 _trash
				(( is_zsh )) && IFS='.' read -A query_arr <<< "$query" || IFS='.' read -a query_arr <<< "$query"
				#query=''
				for key in "${query_arr[@]}"; do
					if [[ "$key" == *","* ]]; then
						#((++i))
						query="$key" # key[0,1]
						query="${query//\[/.{}" # key[0,1] -> key.{0,1]
						query="${query//\]/\}}" # key{0,1] -> key.{0,1}
						if [[ "$query" == *-1* ]]; then 
							local last_el="${json_to_arr_array[${fullkey}${query//\.*}]##* }"
							query="${query//-1/${last_el}}"
						fi
						key="$query"
						#exit
					elif [[ "$key" == *'[]'* ]]; then 
						#((++i))
						#key="${fullkey}${key}"
						key="${key//\[\]}" # key[] -> key
						result="${json_to_arr_array[${fullkey}$key]}"
						#declare -p1 json_to_arr_array
						if [[ "${result::3}" != "@a " ]]; then
							error "${fullkey}${key} is not an array"
							return 1
						elif ! (( ${#result} >= 2 )); then 
							continue
						fi
						key="${key}.{0..${result##* }}" # key.{0..<last element>}
						#echo "$key $result"
					fi
					fullkey+="$key."
				done
				fullkey="${fullkey%%.}"
				eval "printf -v fullkey '%s ' $fullkey"
				for key2 in $fullkey; do
					local key2_value="${json_to_arr_array[$key2]}"
					#echo "$key2 $key2_value"
					[[ -z "$key2_value" ]] && continue
					case "${key2_value::3}" in
						'@A ')
							parse_object "${key2_value//@A }" "$key2"
							json_query_output+=("${parsed_object## }")
							;;
						'@a ')
							parse_array "${key2_value//@a }" "$key2"
							json_pretty_output+=("$parsed_array")
							;;
						*)
						#echo "$key2_value"
							is_true "$raw" && unwrap_string "$key2_value" && key2_value="$raw_string"
							json_query_output+=("${key2_value}")
					esac
				done
				#echo "$result"
				#[[ "${result: -1}" == $'\n' ]] && result="${result::-1}"
			else
				result="${json_to_arr_array[${query}]}"
				if [[ "${result::3}" == '@A ' ]]; then
					parse_object "${result//@A }" "$query"
					result="${parsed_object## }"
				elif [[ "${result::3}" == '@a ' ]]; then
					parse_array "${result//@a }" "$query"
					result="$parsed_array"
				else
					is_true "$raw" && unwrap_string "$result" && result="$raw_string"
				fi
				json_query_output+=("$result")
			fi
		done
	fi
}
#func3 "$1"

json_set() {
	### json_set <key> <value> <sub?>
	## set/append key value to JSON
	## if $sub = false, modified array is built back into JSON and saved as `json_set_output`
	##
	## - if `$shjq_arr` variable is set, its value is used as input array
	json_set_output=''
	local query="$1"
	local value="$2"
	local sub="${3:-false}"

	if [[ "$shjq_arr" && "$shjq_arr" != json_to_arr_array ]]; then
		declare -p "$shjq_arr" >/dev/null 2>&1 || { error "invalid or empty array"; return 1; }
		(( ! is_zsh )) && declare -n json_to_arr_array="$shjq_arr" || typeset -gA json_to_arr_array=("${(kv)${(P)shjq_arr}[@]}");
	fi

  	[[ "$query" == *"[]"* ]] && query="${query//\[\]}" && local append_arr=1
	
	_parse_query

	local parent="${query%\.*}"
	local key="${query##${parent}.}"

	if ! typecheck "$value"; then
		sanitize_string "$value"
		value="$sanitized_string"
	fi

	if [[ "$parent" == "$query" || "${json_to_arr_array[$query]}" ]] && (( ! append_arr )); then
		local type="${value::1}"
		case "$type" in
			'{'|'[') [[ "$type" == '[' ]] && json_to_arr_array[$query]='@a' || json_to_arr_array[$query]='@A'; local pre_parent=("$query") pre_parent_t=("$type"); json_to_arr "$value" "" true true ;;
			*) json_to_arr_array[$query]="$value" ;;
		esac
	else
		case "${json_to_arr_array[$parent]::2}" in
		"@a")
			local index="${json_to_arr_array[$parent]##* }"
			((++index))
			case "${value::1}" in
			'{')
				json_to_arr_array[$parent.$index]="@A"; local pre_parent=("$parent.$index") pre_parent_t=('{'); 
				json_to_arr "$value" "" true true
				declare -p json_to_arr_array
				json_to_arr_array[$parent]+=" $index"
				;;
			'[') error "cannot append array inside another array"; return 1 ;;
			*) 
				json_to_arr_array[$parent]+=" $index"
				json_to_arr_array[$parent.$index]="$value"
		esac
			;;
		"@A")
			(( append_arr )) && { error "cannot append to object"; return 1; }
			local type="${value::1}"
			case "$type" in
				'{'|'[') [[ "$type" == '[' ]] && json_to_arr_array[$query]='@a' || json_to_arr_array[$query]='@A'; local pre_parent=("$query") pre_parent_t=("$type"); json_to_arr "$value" "" true true ;;
				*) json_to_arr_array[$query]="$value" ;;
			esac
			json_to_arr_array[$parent]+=" $key"
			;;
		*)
			(( append_arr )) && error "cannot append to non-array" || error "cannot add a key to non-object"
			return 1
		esac
	fi

	if (( is_zsh )) && [[ "$shjq_arr" ]]; then
		eval "typeset -gA ${shjq_arr}=(\"\${(kv)json_to_arr_array[@]}\")"
	fi
	if ! is_true "$sub"; then
		arr_to_json json_to_arr_array true
		json_set_output="$arr_to_json_output"
	fi
}

json_remove() {
	### json_remove <query> <sub?>
	## remove JSON key/element
	## if $sub = false, modified array is built back into JSON and saved as `json_remove_output`
	##
	## - if `$shjq_arr` variable is set, its value is used as input array
	if [[ "$shjq_arr" && "$shjq_arr" != json_to_arr_array ]]; then
		declare -p "$shjq_arr" >/dev/null 2>&1 || { error "invalid or empty array"; return 1; }
		(( ! is_zsh )) && declare -n json_to_arr_array="$shjq_arr" || typeset -gA json_to_arr_array=("${(kv)${(P)shjq_arr}[@]}");
	fi
	local query="$1"
	local sub="${2:-false}"
 	local result
	
	_parse_query
	local parent="${query%\.*}"
	local key="${query##${parent}.}"
	# if key.key2:
	# $parent = key
	# $key = key2

		#declare -p1 json_to_arr_array
	if [[ "${parent}" != "${key}" ]]; then
		local parent_keys="${json_to_arr_array[${parent}]}"
		if [[ "${parent_keys::3}" == "@a " ]]; then
			if [[ "$key" == -1 ]]; then
				json_to_arr_array[$parent]="${parent_keys% *}"
			else
				parent_keys="${parent_keys:3}"
				json_to_arr_array[$parent]="@a ${parent_keys/ ${key}}"
			fi
		else
			unset json_to_arr_array[${query}]
			json_to_arr_array[$parent]="${json_to_arr_array[${parent}]/${key}}"
		fi
	else
		unset json_to_arr_array[${query}]
	fi

	if (( is_zsh )) && [[ "$shjq_arr" ]]; then
		eval "typeset -gA ${shjq_arr}=(\"\${(kv)json_to_arr_array[@]}\")"
	fi

	if ! is_true "$sub"; then
		arr_to_json json_to_arr_array true
		json_remove_output="$arr_to_json_output"
	fi

}

__need_json_arr() {
	# if last changes was JSON
	if (( last_change == 1 )); then
		json_to_arr "${1:-$_result}"
		last_change=0
	fi
}

__need_json() {
	# if last change was array
	if (( last_change == 2 )); then
		arr_to_json json_to_arr_array true
		_result="$arr_to_json_output"
		last_change=0
	fi
}


__help_msg() {
	code="${1:+1}"
	{	
		[[ "$1" ]] && echo "Invalid option: $1"
		cat << EOF
${FUNCNAME[1]:-$0} [input?] [operation] [operation] [modifier] ...
EOF
		echo -e "$shjq_help"
	} >&2
	exit "${code:-0}"
}


__ver_msg() {
echo "shelljq $SHELLJQ_VERSION
Copyright (C) 2026 Tirito6626

https://github.com/Tirito6626/shelljq"
}
__docs() {
	echo -e "$shjq_docs" | less -R
}

shjq() {
	#set -x
	#- 
	#- input can be JSON or a file; if no input provided, shjq tries reading from STDIN with 1 second timeout, and exits if no data to read
	#- 
	#- each operation is performed in consecutive order and its output becomes the input for the next operation
	#- '--raw' only applies on the next operation(s) in order
	#- 
	#set -x
	if [[ -n "$1" && '{[' == *"${1::1}"* ]]; then
		input="${1}"
		#shift
		if (( $# > 1 )); then
			shift
			local args=("${@}")
		else
			local args=("-t")
		fi
	elif [[ -f "$1" ]]; then
		read -r -d $'\0' input <"$1";
		if (( $# > 1 )); then
			shift
			local args=("${@}")
		else
			local args=("-t")
		fi
	#	shift
	else
		#- informative:
		case "$1" in
			##- print this message
			("-h"|"--help")
				__help_msg
				return 
				;;
			##- print version
			("-v"|"--version")
				__ver_msg
				return
				;;
			*) 
				if read -r -t 1 input; then
					while read -r; do
						input+="$REPLY"
					done
					input+="$REPLY"
				else
					error "no input provided"
					__help_msg
					return 1
				fi
		esac
		local args=("${@}")
	fi
	[[ -z "$input" ]] && error "no input provided" && __help_msg && return 1;
	#set +x
	local i=0 raw=false pretty=false join_output=false last_change=0
	# last_change:
	# - 0: no changes
	# - 1: JSON was updated, may need to be converted into array
	# - 2: array was modified, may need to be converted back into JSON
	local actions=()
	local _result="$input"
	#echo "${args[@]}"
	case "${args[0]}" in
		-c|-t|--trim)
			if [[ "${#args[@]}" == 1 ]]; then
				json_trim "$input" true || { echo "validation error: $__shjq_error"; return 1; }
				return
			else
				json_trim "$input" true true || { echo "validation error: $__shjq_error"; return 1; }
				last_change=1
				_result="$json_trim_output"
				((++i))
			fi
			;;
		-p|--pretty)
			if [[ "${#args[@]}" == 1 ]]; then
				json_trim "$input" true true || { echo "validation error: $__shjq_error"; return 1; }
				json_pretty "$json_trim_output"
				return $?
			fi
			;;
		-T|--no-trim)
			json_to_arr "$_result"
			last_change=0
			((++i))
			;;
		*)
			json_trim "$input" true true || { echo "validation error: $__shjq_error"; return 1; }
			_result="$json_trim_output"
			json_to_arr "$json_trim_output"
			last_change=0
			;;
	esac
	#set +x
	#declare -p args
	for ((i=i; i<${#args[@]}; i++)); do
		local arg="${args[$i]//\'}"
		[[ -z "$arg" ]] && continue
		case "$arg" in	
		#- convertion:
		##- convert JSON into associative array and generate its declaration string
		("-A"|"--to-arr"|"--to-array")
			__need_json_arr
			declare -p json_to_arr_array
			return
			;;
		#- JSON operations (chained):
		##- QUERY; perform a JSON query. for multi-query use space-separated list in quotes: "key key2 key3 ..."
		("-rq"|"-q"|"--query")
			__need_json_arr
			[[ "$arg" == "-rq" ]] && raw=true
			case "${args[$i+2]}" in
				"-r"|"--raw") raw=true; ;;
			esac
			json_query "${args[$i+1]}" "${raw}" true || { echo "query error: $__shjq_error"; return 1; }
			_result="${json_query_output}"
			#echo "$_result"
			last_change=1
			((++i))
			(( multi_output )) && results=("${json_query_output[@]}")
			#echo "$_result ${results[@]}"
			;;
		##- trim JSON
		("-t"|"--trim")
			__need_json
			last_act=trim
			json_trim "$_result" "${validate}" true
			[[ $i < ${#args[@]} ]] && _result="$json_trim_output" || json_to_arr "$json_trim_output"
		;;
		##- KEY VALUE; modify JSON. if KEY includes '[]', the VALUE is appended to KEY array as new element instead of rewriting the value
		("-a"|"--append"|"-s"|"--set")
			__need_json_arr
			json_set "${args[$i+1]}" "${args[$i+2]}" true
			last_change=2
			i=$((i+2))
			;;
		##- KEY; remove JSON key/element. if index is specified, unset individual index instead
			("-r"|"--remove"|"-d"|"--delete")
			__need_json_arr
			json_remove "${args[$i+1]}" true
			last_change=2
			((i++))
			;;
	#- modifiers:
		##- pretty output
		("-p"|"--pretty")
			pretty=true
			;;
		##- print raw output
		("-r"|"--raw")
			raw=true
			;;
		##- DELIM; join multiple outputs in one line with DELIM
		("-j"|"--join")
			join_output=true
			[[ "${args[$i+1]}" ]] && delimiter="${args[$i+1]}"
			((++i))
			;;
		##- compact output. disables '--pretty'
		("-c"|"--compact")
			pretty=false
			;;
		*)
			__help_msg "${args[$i]}"
			return
			;;
		esac
	done
	#- 
	#- if no operation is specified, '--trim' is performed by default
	__need_json
	#set +x
	#set -x
	if ((multi_output)); then
		if is_true "$pretty"; then
			for ((i=0;i<${#results[@]};i++)); do
				local result="${results[$i]}"
				[[ -z "$result" ]] && continue
				if [[ '{[' == *"${result::1}"* ]]; then
					json_pretty "$result" true || { echo "validation error: $__shjq_error"; return 1; }
					results[$i]="${json_pretty_output%%$'\n'}"
				fi
			done
		fi

		if is_true "$join_output"; then
			IFS="${delimiter:- }" 
			echo "${results[*]}"
			unset IFS
		else
			printf "%s\n" "${results[@]}"
		fi
	elif is_true "$pretty" && [[ '{[' == *"${_result::1}"* ]]; then
		__need_json
		json_pretty "$_result" false || { echo "validation error: $__shjq_error"; return 1; }
	else
		printf "%s\n" "$_result"
	fi
}
(( sourced )) || { shjq "$@"; exit $?; }