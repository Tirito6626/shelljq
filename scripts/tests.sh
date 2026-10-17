#!/usr/bin/env bash
dir="$(dirname "$0")"
dir="${dir//$0}"
_path="${dir}/../shjq"
if [[ ! -f "$_path" ]]; then
    path="${path/shjq/main.sh}"
    if [[ ! -f "$_path" ]]; then 
        echo "${path/main.sh/shjq} missing" >&2
        exit 1
    fi
fi
#echo "$PATH"
if [[ "$ZSH_VERSION" ]]; then
    emulate ksh
    zmodload zsh/datetime zsh/mathfunc
    setopt continue_on_error
	function time_ms { printf -v "${1:-ms}" "$(( int(EPOCHREALTIME * 1000) ))"; }
    function expand_or_string {
        [[ "$1" != *[0-9]* && -v "${1}" ]] && printf -v "$2" '%s' "${(P)1}" || printf -v "$2" '%s' "$1"
    }
	#function _to_lowercase { local var="${(P)1}"; printf -v "$1" "%s" "${var:l}"; }
else
	function time_ms { ms="${EPOCHREALTIME//[.,]/}"; printf -v "${1:-ms}" "${ms::-3}"; }
	function expand_or_string {
        [[ -v "${1}" ]] && printf -v "$2" '%s' "${!1}" || printf -v "$2" '%s' "$1"
    }
    #function _to_lowercase { local var="${!1}"; printf -v "$1" "%s" "${var,,}"; }
fi

declare -gA test_array=(
    [foo]="bar \" baz"
    [key]="@A key1 key2 key3"
    [key2]="[{\"foo\":\"bar\"}]"
    [key.key1]="string test"
    [key.key2]=35.2
    [key.key3]="@a 0 1 2 3"
    [key.key3.0]="another string"
    [key.key3.1]="foo \" bar"
    [key.key3.2]=null
    [key.key3.3]="@A foo"
    [key.key3.3.foo]="bar"
)

declare -A test_key_output=(
    [key3.3.foo]="bar" 
    [key3.3]="@A foo" 
    [key3.2]="null"
    [key3.1]="foo \" bar"
    [key3.0]="another string"
    [key2]="35.2"
    [key3]="@a 0 1 2 3" 
    [key1]="string test" 
)

#long_input="$(cat "$dir/test.json")"

test_strings=(
    '{ "foo": "bar" }'
    '{ 
        "foo": "bar"
    }'
    '{ "foo": "bar baz" }'
    '[{ "foo": "bar baz" }]'
    '{ "foo": "bar\"baz" }'
    "$(cat "$dir/test.json")"
)
#declare -p test_strings
test_outputs=(
    '{"foo":"bar"}'
    '{"foo":"bar"}'
    '{"foo":"bar baz"}'
    '[{"foo":"bar baz"}]'
    '{"foo":"bar\"baz"}'
    '{"component":{"type":17,"accent_color":16777215,"spoiler":false,"components":[{"type":9,"accessory":{"type":11,"media":{"url":"https://tirito.de/assets/kcalb.webp","proxy_url":"https://tirito.de/assets/kcalb.webp"},"description":null,"spoiler":false},"components":[{"type":10,"content":"## grand _tirito_'\''s portfolio"}]},{"type":1,"components":[{"type":2,"style":5,"label":"Fiction","emoji":null,"disabled":false,"url":"https://github.com/FictionWeb/framework"},{"type":2,"style":5,"label":"Amber","emoji":null,"disabled":false,"url":"https://amber-lang.com"},{"type":2,"style":5,"label":"Wispbyte","emoji":null,"disabled":false,"url":"https://wispbyte.com"},{"type":2,"style":5,"label":"all projects","emoji":null,"disabled":false,"url":"https://github.com/Tirito6626"}]},"tets\"\", fine okl"]},"hello":"1 2 3"}'
    '{"foo":"bar \" baz","key":{"key1":"string test","key2":35.2,"key3":["another string","foo \" bar",null,{"foo":"bar"}]},"key2":[{"foo":"bar"}]}'
)

#long_output='{"component":{"type":17,"accent_color":16777215,"spoiler":false,"components":[{"type":9,"accessory":{"type":11,"media":{"url":"https://tirito.de/assets/kcalb.webp","proxy_url":"https://tirito.de/assets/kcalb.webp"},"description":null,"spoiler":false},"components":[{"type":10,"content":"## grand _tirito_'\''s portfolio"}]},{"type":1,"components":[{"type":2,"style":5,"label":"Fiction","emoji":null,"disabled":false,"url":"https://github.com/FictionWeb/framework"},{"type":2,"style":5,"label":"Amber","emoji":null,"disabled":false,"url":"https://amber-lang.com"},{"type":2,"style":5,"label":"Wispbyte","emoji":null,"disabled":false,"url":"https://wispbyte.com"},{"type":2,"style":5,"label":"all projects","emoji":null,"disabled":false,"url":"https://github.com/Tirito6626"}]},"tets\"\", fine okl"]},"hello":"1 2 3"}'

function _end() {
    (( skipped )) || unset skipped
    time_ms
    if (( succeeded == tests )); then 
        printf "%s " "tests: ${_green}ok${_nc}"
        local code=0
    else
        printf "%s " "tests: ${_red}fail${_nc}"
        local code=1
    fi
    printf "%s\n" "(${succeeded}/${tests}${skipped+, $skipped skipped}) ($((ms-test_start))ms)"
    exit ${code:-0}
}

source "$_path"
#set -e
[[ "$1" ]] && target="$1"
declare -i tests=0 succeeded=0 skipped=0
@test() {
    echo "$1()"
    test_func="$1"
}

test() {
    [[ "$target" && "$target" != "$1" ]] && skipped+=1 && return
    tests+=1
    local start
    local args="${show_args:-${*:2}}"
    time_ms start
    if "${@:1}"; then
        time_ms
        echo "test '$1 ${args}' ${_green}✓${_nc} ${_gray}$((ms-start))ms${_nc}"
        succeeded+=1
    else
        time_ms 
        echo "test '${1} ${args}' ${_red}x${_nc} (\$? $? != 0) ${_gray}$((ms-start))ms${_nc}"
        [[ "$__shjq_error" ]] && echo "${_gray}> ${_red}$__shjq_error${_nc}"
        return 1
    fi
}

!test() {
    [[ "$target" && "$target" != "$1" ]] && skipped+=1 && return
    tests+=1
    local start
    local args="${show_args:-${*:2}}"
    time_ms start
    if "${@:1}"; then
        echo "test ! '$1 $args' ${_red}x${_nc} (\$? $? != 1)"
        return 1
    else
        time_ms
        echo "test ! '$1 $args' ${_green}✓${_nc} ${_gray}$((ms-start))ms${_nc}"
        succeeded+=1
    fi
}

assert() {
    [[ "$target" && "$target" != "$1" ]] && skipped+=1 && return
    tests+=1
    expand_or_string "$1" left
    expand_or_string "$2" right
    if [[ "$left" != "$right" ]]; then
        echo "assertion failed: $1 == $2"
        git diff --minimal --no-index --word-diff=color --word-diff-regex=. <(echo "$left") <(echo "$right")
        return 1
    else
        (( log )) && echo "${_gray}+ assertion $1 == $2 ${_green}✓${_nc}"
    fi
    succeeded+=1
}

assert_arr() {
    [[ "$target" && "$target" != "$1" ]] && skipped+=1 && return
    tests+=1
    if (( is_zsh )); then
        typeset -lA left_arr=("${(kv)${(P)1}[@]}")
        typeset -lA right_arr=("${(kv)${(P)2}[@]}")
		local keys=("${(k)${(P)arrname}[@]}")
	else
		declare -ln left_arr="$1"
        declare -ln right_arr="$2"
		local keys=("${!left_arr[@]}")
	fi
    for key in "${keys[@]}"; do
        local left="${left_arr[$key]}"
        local right="${right_arr[$key]}"
        if [[ "$left" != "$right" ]]; then
            echo "assertion failed: $1[$key] == $2[$key]"
            echo "'$left' != '$right'"
            declare -p "$1" 
            declare -p "$2"
            return 1
        fi
    done

    (( log )) && echo "${_gray}+ assertion $1[] == $2[] ${_green}✓${_nc}"
    succeeded+=1
}

!assert() {
    [[ "$target" && "$target" != "$1" ]] && skipped+=1 && return
    tests+=1
    expand_or_string "$1" left
    expand_or_string "$2" right
    if [[ "$left" == "$right" ]]; then
        echo "assertion failed: $1 == $2"
        return 1
    fi
    succeeded+=1
}

time_ms test_start
log=1

# is_true
test is_true true
test is_true 1

!test is_true false
!test is_true 0

# sanitize_string
sanitize_string "test\"string"
assert sanitized_string '"test\"string"'

sanitize_string '"test string'
assert sanitized_string '"\"test string"'

# unwrap_string
unwrap_string '"foo \" bar"'
assert raw_string 'foo " bar'

unwrap_string '"\"foo bar\""'
assert raw_string '"foo bar"'

# bool_to_int
var="true"
bool_to_int var
assert "$var" 1

var="false"
bool_to_int var
assert "$var" 0

var="test"
test bool_to_int var
assert "$var" 0

var="1"
test bool_to_int var
assert "$var" 1
#set +x
# typecheck
test typecheck '"test"' string
test typecheck '"test \" string"' string
test typecheck 2.5 int
test typecheck -0.5683 int
test typecheck false bool
test typecheck null null
test typecheck true bool
test typecheck '{ "foo": "bar" }' object
test typecheck '{}' object
test typecheck '{"foo": "{\"bar\":\"baz\"}"}' object
test typecheck '[1, 2, 3]' array
test typecheck '[{ "foo": "bar" }]' array
test typecheck '[]' array

!test typecheck 'test' string
!test typecheck '"test " string"' string

!test typecheck '"test' string
!test typecheck 2.5ed int
!test typecheck 2d2 int
!test typecheck test bool
!test typecheck '{test}' object
#!test typecheck '{"foo": {"bar"}}' object # todo
!test typecheck '[test]' object
set +x

# json_trim
for ((i=0; i<${#test_strings[@]}; i++)); do
    input="${test_strings[$i]}"
    output="${test_outputs[$i]}"
    if show_args="test_strings[$i]" test json_trim "$input" true true; then
        log=1 assert json_trim_output output
    else
        echo "${_gray}test_strings[$i]: $input"
    fi
done

# arr_to_json
test arr_to_json test_array true
assert "arr_to_json_output" "${test_outputs[-1]}"

# key_to_arr
declare -A output_arr
sub=1 test key_to_arr key output_arr true test_array
assert_arr output_arr  test_key_output
sub=1 !test key_to_arr key "" true

#json_to_arr
test_array[key2]="@a 0"
test_array[key2.0]="@A foo"
test_array[key2.0.foo]="bar"
test json_to_arr "$arr_to_json_output" '' '' true
assert_arr json_to_arr_array test_array
_end