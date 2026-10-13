path="$(dirname "$0")"
path="${path//$0}/../shjq"
if [[ ! -f "$path" ]]; then
    path1="${path/shjq/main.sh}"
    if [[ ! -f "$path1" ]]; then 
        echo "$path and $path1 missing" >&2
        exit 1
    fi
    if [[ "$1" == 3 ]]; then
        input=$(grep -v -e '	#' -e '###' -e '## [^}]' -e '^##$' -e '#- ' "$path1")
    else
        input=$(grep -v '#- ' "$path1")
    fi
else
    input=$(grep -v '#- ' "$path")
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
			gsub(/\"/, "");
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

if [[ "$1" ]]; then
    echo "${input//<help placeholder>/${output//$/\\$}}" > "$path"
else
    echo "$output"
fi