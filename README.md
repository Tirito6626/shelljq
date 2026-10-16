# shelljq
bash 4.3+/zsh JSON processor

# FORMAT
shelljq uses own array format for storing multi-dimensional objects in two-dimensional array (indexed arrays are not supported).
by default, root array is assumed to be an object, unless it contains `_shjq_arr` key and its value is 1, then the array is parsed as JSON array
bash array keys can represent:
- integers, null and booleans, saved as literals
```bash
[key]=1
[key]=true
[key]=null
```
- literal string, wrapped in double quotes by default
```bash
[key]='"value"' # or 'value' if raw
```
- JSON objects and have prefix `@A ` in value (as in -A, associative) with top children keys in a list, separated with spaces
```bash
# { "key": { "key1": "bar", "key2": "baz", "key3": { "foo": "bar" } } }
[key]='@A key1 key2 key3'
[key.key1]='"bar"'
[key.key2]='"baz"'
[key.key3]='@A foo'
[key.key3.foo]='"bar"'
```
- JSON arrays and have prefix `@a ` in value (as in -a, indexed) with each element index, separated with spaces
```bash
# { "key": [ "foo", "bar", "baz" ] }
[key]='@a 0 1 2'
[key.0]='"foo"'
[key.1]='"bar"'
[key.2]='"baz"'
```
`@A ` and `@a ` serve as markers for JSON objects/arrays and contains pointers to its children. if you manually remove one of the keys from `@A ...` or `@a ...`, it will be ignored by the parser and not added into the JSON
by design this format is made for convenient and simple JSON projection onto associative array without enforcing types or being strict

# QUERY
follows similar to JQ(1)'s basic query syntax without the leading dot
- key
- key.subkey
- arr[] -> return each element individually
- arr[].key
- arr[1,2].key
- arr[-1,2].key -> -1 resolves to `arr`s last index

# FUNCTIONS

# is_true `value` -> $? (0 | 1)
returns 0 or 1 depending on the $value (1/true = 0, 0/false = 1, * = 1)

# bool_to_int `var`
convert $var's value into 1 or 0

# int_to_bool `var`
convert $var's value into literal `true` or `false`

# typecheck `value` `type?` -> $? (0 | 1)
supported types:
1/string, 2/int, 3/bool, 4/null, 5/object, 6/array
if no $type supplied, the value is checked with every type

# json_trim `input` `validate?` `sub?` -> json_trim_output
trim JSON
if $validate = true, the input is validated for structure and individual values (slower)
if $sub = true, output is only saved into `json_trim_output` instead of being printed

# arr_to_json `arr_name` `sub?` `pretty?` -> arr_to_json_output
convert associative array into JSON
if $sub = true, output is only saved into `arr_to_json_output` instead of being printed
if $pretty = true, additionally appends indentation and value highlight

# json_pretty `input` `sub?` -> json_pretty_output
returns JSON input with highlight and indentation (pretty-print)
unlike `json_to_arr` with $pretty option,
if $sub = true, output is only saved into `json_pretty_output` instead of being printed

# profiler
used inside bash DEBUG trap, returns the execution time of each operation/command in μs

# key_to_arr `key` `arr_name` `raw?` `source_arr?` -> json_to_arr_array[] | `name`[]
build a new array from a key object/array
if $raw = true, it's passed to `json_to_arr`
if $source_arr is supplied, it's used as reference (exclusive to bash runtime) (default is json_to_arr_array)

# json_to_arr `input` `arrname?` `prefix?` `raw?` `return?` -> json_to_arr_array[] | `name`[] | json_to_arr_output
if $arrname is supplied, it's used as array reference (exclusive to bash runtime) (default is json_to_arr_array)
if $prefix is supplied, it's prepended to each key name
if $raw = true, all key string values are saved without the quoting
if $return = true, declaration string of generated array is saved in `json_to_arr_output`

# json_query `query(s)` `raw?` `sub?` -> json_query_output[]
perform JSON query
if $raw = true, double quotes are removed from the output (if the output is a string)
if $sub = true, $input is omitted, otherwise $input is used as JSON input and converted into array

# json_set `key` `value` `sub?` `arrname?`
set/append key value to JSON
if $sub = false, modified array is built back into JSON and saved as `json_set_output`
if $arrname is supplied, it's used as array reference (exclusive to bash runtime) (default is json_to_arr_array)

# json_remove `query` `sub?`
remove JSON key/element
if $sub = false, modified array is built back into JSON and saved as `json_remove_output`

