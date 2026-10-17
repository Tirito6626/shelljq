dir="$(dirname "$0")"
dir="${dir//$0}"
path="${dir}/../shjq"
if [[ ! -f "$path" ]]; then
    path1="${path/shjq/main.sh}"
    if [[ ! -f "$path1" ]]; then 
        echo "$path and $path1 missing" >&2
        exit 1
    fi
    input=$(grep -v -e '	#' -e '###' -e '## [^}]' -e '^##$' "$path1")
else
    input=$(grep -v -e '	#' -e '###' -e '## [^}]' -e '^##$' "$path")
fi

output="# shelljq
bash 4.3+/zsh native JSON processor

- no external commands needed
- no subshells
- one file
- JSON validation and typechecking (as far as it goes in shell)

# INSTALLATION
the GitHub repository includes main.sh, shjq and shjq-full in 'Releases' tab

## main.sh 
the raw source file including the code, documentation, letfover comments and notes

## shjq
extra generated shell script with pregenerated help message, excluding documentation and comments

## shjq-full
full script package including documentation and help message

depending on your need, you will most likely only need the 'shjq' file for the minimal file size, since the documentation is also generated into README
"

#echo "${input/<docs placeholder>/$docs}"
if [[ "$1" ]]; then
    while read line; do
	    line="${line## }"
	    case "${line::3}" in
		    "###")
			    output+="\\n\\\\033[1m${line:4}\\\\033[0m"$'\n'
			    ;;
		    "## ")
		    	output+="${line:2}"$'\n'
		esac
    done <"${path1:-$path}"
    #input="$(cat "$path")"
    output="${output//$/\\$}"
    output="${out//\"/\\\"}"
    output="${output//\`/\\\`}"
    echo "${input//<docs placeholder>/${output//$/\\$}}" > "$path"
else

    #set -x
    while read line; do
	    line="${line## }"
        line="${line//</\`}"
        line="${line//>/\`}"
        line="${line//-\`/->}"
        #echo "$line"
	    case "${line::3}" in
            "## ") output+="${line:3}"$'\n' ;;
            "###") output+=$'\n'"${line:2}"$'\n' ;;
        esac
    done <"${path1:-$path}"
    set +x
    [[ "$output" ]] && echo "$output" > "$dir/../README.md"
fi
#sed -i "s#\<docs placeholder\>#${docs//$'\n'/\\n}#" "$path"