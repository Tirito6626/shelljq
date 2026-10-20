dir="$(dirname "$0")"
dir="${dir//$0}"
path="$dir/../shjq"
path1="${path/shjq/main.sh}"
if [[ -f "$path" ]]; then
    if [[ ! -f "$path1" ]]; then 
        echo "$path and $path1 missing" >&2
        exit 1
    fi
    rm "$path"
    #path="$path1"
    #if [[ "$1" == 3 ]]; then
    #    input=$(grep -v -e '	#' -e '###' -e '	##' -e '^## ' -e '#- ' "$path1")
    #else
        input=$(grep -v '#- ' "$path1")
    #fi
else
    input=$(grep -v '#- ' "$path1")
fi

output=$(awk '/##\- / {
			gsub(/	/, "");
			sub(/##-/, "");
			line = $0;
			args = "";
			if (line ~ ";") {
				split($0, a, ";");
				args = a[1];
				line = a[2];
			}
			getline;
			gsub(/	/, "");
			sub(/\(/, "");
			sub(/\)/, "");
			gsub(/"/, "");
			gsub(/\|/, ", ");
			split($0, opts, ", ")
			if (4 in opts) {
				opt = $0;
				trash = opts[1]", "opts[2]", "opts[3]", ";
				sub(trash, "", opt);
				len = length(opt) + length(args);
				opt = trash "\n  " opt;
			} else {
				opt = $0;
				len = length($0) + length(args);
			}

			pad = sprintf("%*s", 27 - len, " ");
			printf("  %s%s%s%s\n", opt, args, pad, line);
		};
		/#\- / {
			gsub(/	/, "");
			sub(/#\- /, "");
			print
		}
' "${path1:-$path}")
docs="# shelljq
bash 4.3+/zsh native JSON processor

- no external commands needed
- no subshells
- one file
- JSON validation and typechecking (as far as it goes in shell)
"
while read line; do
	orig_line="$line"
	line="${line## }"
    line="${line//</\`}"
    line="${line//>/\`}"
    line="${line//-\`/->}"
	case "${line::3}" in
        "## ") docs+="${line:3}"$'\n' ;;
        "###") docs+=$'\n'"${line:2}"$'\n' ;;
    esac
done <<< "$input"
input="${input//<help placeholder>/${output//$/\\$}}"

echo "$docs" > "$dir/../README.md"

echo "${input//<help placeholder>/${output//$/\\$}}" | grep -v -e '	#' -e '###' -e '	##' -e '^## ' -e '#- ' > "$path"
bash -n "$path"