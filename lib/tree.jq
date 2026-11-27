# The dataset definition's format and its validator, a jq module over the definition: tree_errors
# yields each refusal as {entry, message}, in the definition's order. Included by lib/tree.sh.
#
# A definition is one JSON object with four keys:
# - contexts: the top-level contexts. An explicit context is {name, contexts?}; a query context is
#   {name, filter}, a leaf whose filter is Mikoshi's: a non-empty list of {field, op, value}
#   conditions on route, kind, or duration. A context's path is its names from the top joined
#   with /, such as share/psyops.
# - files: one entry a file, {id, name, contexts: [path...], live?, supersedes?}, with exactly one
#   provenance: {url, sha256, bytes, credit}; {manual: [step...], sha256, bytes, credit} for a file
#   no script can download; {corpus}, a docs-corpus path, whose sha256 is in docs-corpus's
#   MANIFEST.json; or {generated, sha256}, an authored office file by its generator's output name.
#   A new version is a new entry naming the older one's id in supersedes.
# - records: one entry an authored JSON record, {id, annotates: [file id...], contexts: [path...]},
#   whose body is records/<id>.json beside the definition.
# - live_steps: the context steps made in the client, in order, each against the tree as the
#   steps before it left it: {op: "create", path, filter?}, {op: "rename", path, name}, or
#   {op: "move", path, parent, name?}. The load never creates a context a step creates.
#
# Files and records join explicit contexts the definition declares, by their paths at the load.

# One refusal, of the entry given.
def problem($entry; $message): {entry: $entry, message: $message};

# The shape of a file's or a record's id, which names its record body.
def id_pattern: "^[a-z0-9][a-z0-9._-]*$";

# The fields a query context's filter may test, and the operators that take one scalar value.
def filter_fields: ["route", "kind", "duration"];
def scalar_ops: ["eq", "ne", "gt", "ge", "lt", "le", "like"];

# The keys that name a file's provenance, and the keys each provenance requires.
def provenances: ["url", "manual", "corpus", "generated"];
def provenance_keys: {
  url: ["sha256", "bytes", "credit"],
  manual: ["sha256", "bytes", "credit"],
  corpus: [],
  generated: ["sha256"]
};

# The input's key, as a list, or the empty list when the key is absent or holds no list.
def list($key): if (.[$key] | type) == "array" then .[$key] else [] end;

# Whether the input is a context's or a file's name: a non-empty string without /.
def name_ok: type == "string" and length > 0 and (contains("/") | not);

# Whether the input is a non-empty string.
def text: type == "string" and length > 0;

# Whether the input is a value Mikoshi's filter takes: a string, number, or boolean.
def scalar: type | IN("string", "number", "boolean");

# The path above the input path, the empty string for a top-level path.
def dirname: split("/") | .[:-1] | join("/");

# The path of the name given under the input path.
def under($name): if . == "" then $name else "\(.)/\($name)" end;

# The refusals of the input object's keys outside the ones given.
def unknown_keys($allowed; $entry):
  if type == "object" then
    keys_unsorted[] | select(IN($allowed[]) | not)
    | problem($entry; "\(.) is not a key here; the keys are \($allowed | join(", "))")
  else empty end;

# The refusals of an id.
def id_errors($entry):
  if (.id | type) != "string" or (.id | test(id_pattern) | not) then
    problem($entry;
      "id must be lowercase letters, digits, dots, hyphens, and underscores, from a letter or digit")
  else empty end;

# The refusals of a query context's filter, by Mikoshi's rules.
def filter_errors($entry):
  if type != "array" or length == 0 then
    problem($entry; "filter must be a non-empty list of {field, op, value} conditions")
  else
    to_entries[] | .key as $i | .value as $c | "filter[\($i)]" as $at
    | if ($c | type) != "object" then problem($entry; "\($at) must be a {field, op, value} condition")
      else
        ($c | unknown_keys(["field", "op", "value"]; $entry) | .message |= "\($at): " + .),
        (if $c.field | IN(filter_fields[]) | not then
           problem($entry; "\($at).field must be one of \(filter_fields | join(", "))")
         else empty end),
        (if $c.op | IN(scalar_ops[]) then
           if ($c | has("value") | not) or ($c.value | scalar | not) then
             problem($entry; "\($at): op \($c.op) takes one value, a string, number, or boolean")
           else empty end
         elif $c.op == "in" then
           if ($c.value | type) != "array" or ($c.value | length) == 0
              or any($c.value[]; scalar | not) then
             problem($entry; "\($at): op in takes a non-empty list of strings, numbers, or booleans")
           else empty end
         elif $c.op | IN("null", "notnull") then
           if $c | has("value") then problem($entry; "\($at): op \($c.op) takes no value; remove it")
           else empty end
         else
           problem($entry; "\($at).op must be one of \(scalar_ops | join(", ")), in, null, notnull")
         end)
      end
  end;

# The refusals of the contexts list under the path given, as a list of names: each context's keys,
# name, and filter, a query context's children, and siblings sharing a name.
def context_errors($prefix):
  (if $prefix == [] then "definition" else "context \($prefix | join("/"))" end) as $owner
  | if type != "array" then
      problem($owner; "contexts must be a list of {name, contexts} or {name, filter}")
    else
      (to_entries[] | .key as $i | .value as $c
       | (if ($c | type) == "object" and ($c.name | name_ok) then
            "context \($prefix + [$c.name] | join("/"))"
          else "\($owner): contexts[\($i)]" end) as $entry
       | if ($c | type) != "object" then
           problem($entry; "must be {name, contexts} or {name, filter}")
         else
           ($c | unknown_keys(["name", "contexts", "filter"]; $entry)),
           (if $c.name | name_ok | not then
              problem($entry; "name must be a non-empty string without /")
            else empty end),
           (if $c | has("filter") then
              ($c.filter | filter_errors($entry)),
              (if $c | has("contexts") then
                 problem($entry; "a query context is a leaf; remove its contexts or its filter")
               else empty end)
            elif ($c | has("contexts")) and ($c.name | name_ok) then
              $c.contexts | context_errors($prefix + [$c.name])
            else empty end)
         end),
      ([.[] | objects | .name | select(name_ok)] | group_by(.)[] | select(length > 1)
       | problem("context \($prefix + [.[0]] | join("/"))";
           "\(length) sibling contexts share the name \(.[0]); rename all but one"))
    end;

# The declared contexts under the path given, as a list of names, each {key: path, value: kind}.
def declared_nodes($prefix):
  if type == "array" then
    .[] | objects | select(.name | name_ok) | ($prefix + [.name]) as $path
    | {key: ($path | join("/")), value: (if has("filter") then "query" else "explicit" end)},
      (select(has("filter") | not) | .contexts | declared_nodes($path))
  else empty end;

# The contexts the definition declares, as {path: "explicit" or "query"}.
def declared: [.contexts | declared_nodes([])] | from_entries;

# The refusals of a file's or a record's context paths, against the contexts given.
def path_errors($entry; $nodes):
  if type != "array" or length == 0 then
    problem($entry; "contexts must be a non-empty list of context paths, such as share/psyops")
  else
    (.[] | . as $path
     | if type != "string" then problem($entry; "context paths are strings, such as share/psyops")
       elif $nodes[$path] == "query" then
         problem($entry; "\($path) is a query context, which holds only what its filter selects;"
           + " place the entry in an explicit context")
       elif ($path | split("/") | . as $parts
             | any(range(1; length); $nodes[$parts[:.] | join("/")] == "query")) then
         problem($entry; "\($path) sits under a query context, which is a leaf;"
           + " place the entry in an explicit context")
       elif $nodes[$path] == null then
         problem($entry; "\($path) is not a declared context; declare it or fix the path")
       else empty end),
    (group_by(.)[] | select(length > 1) | problem($entry; "lists \(.[0]) twice; list it once"))
  end;

# The refusals of a file entry, at the index given, against the contexts and file ids given.
def file_errors($i; $nodes; $file_ids):
  . as $f
  | (if type == "object" and (.id | type) == "string" then "file \(.id)" else "files[\($i)]" end)
    as $entry
  | if type != "object" then problem($entry; "must be an object")
    else
      unknown_keys(["id", "name", "contexts", "live", "supersedes", "sha256", "bytes", "credit"]
        + provenances; $entry),
      id_errors($entry),
      (if .name | name_ok | not then
         problem($entry; "name must be the file's name, a non-empty string without /")
       else empty end),
      (.contexts | path_errors($entry; $nodes)),
      (if has("live") and (.live | type) != "boolean" then
         problem($entry; "live must be true or false")
       else empty end),
      (if has("supersedes") | not then empty
       elif .supersedes == .id then
         problem($entry; "supersedes names the entry itself; give the older entry's id")
       elif .supersedes | IN($file_ids[]) | not then
         problem($entry; "supersedes \(.supersedes | tojson) names no file; give the older entry's id")
       else empty end),
      ([provenances[] as $key | select($f | has($key)) | $key] as $have
       | if ($have | length) != 1 then
           problem($entry; "needs exactly one provenance, url, manual, corpus, or generated;"
             + " it has \(if $have == [] then "none" else $have | join(", ") end)")
         else
           $have[0] as $p | provenance_keys[$p] as $need
           | ((["sha256", "bytes", "credit"] - $need)[] | select(. as $key | $f | has($key))
              | problem($entry; "a \($p) file carries no \(.)"
                  + (if $p == "corpus" and . == "sha256" then
                       ", fetch reads it from docs-corpus's MANIFEST.json"
                     else "" end) + "; remove it")),
             ($need[] | select(. as $key | $f | has($key) | not)
              | problem($entry; "a \($p) file needs \(.); add it")),
             (if $p == "url" and (.url | type == "string" and test("^https?://\\S+$") | not) then
                problem($entry; "url must be an http or https URL")
              elif $p == "manual" and ((.manual | type) != "array" or (.manual | length) == 0
                   or any(.manual[]; text | not)) then
                problem($entry; "manual must be a non-empty list of the steps to fetch the file")
              elif $p == "corpus" and (.corpus | text and (startswith("/") | not)
                   and (split("/") | index("..") | not) | not) then
                problem($entry; "corpus must be a relative path inside docs-corpus")
              elif $p == "generated" and (.generated | name_ok | not) then
                problem($entry; "generated must be the generator's output file name")
              else empty end),
             (if ($need | index("sha256")) and has("sha256")
                 and (.sha256 | type == "string" and test("^[0-9a-f]{64}$") | not) then
                problem($entry; "sha256 must be 64 lowercase hex characters")
              else empty end),
             (if ($need | index("bytes")) and has("bytes")
                 and (.bytes | type == "number" and . == floor and . > 0 | not) then
                problem($entry; "bytes must be the file's size, a whole number over 0")
              else empty end),
             (if ($need | index("credit")) and has("credit") and (.credit | text | not) then
                problem($entry; "credit must be a non-empty string")
              else empty end)
         end)
    end;

# The refusals of a record entry, at the index given, against the contexts and file ids given.
def record_errors($i; $nodes; $file_ids):
  (if type == "object" and (.id | type) == "string" then "record \(.id)" else "records[\($i)]" end)
    as $entry
  | if type != "object" then problem($entry; "must be an object")
    else
      unknown_keys(["id", "annotates", "contexts"]; $entry),
      id_errors($entry),
      (if (.annotates | type) != "array" or (.annotates | length) == 0 then
         problem($entry; "annotates must be a non-empty list of file ids")
       else
         .annotates[] | select(IN($file_ids[]) | not)
         | problem($entry; "annotates \(tojson), which names no file; give a file's id")
       end),
      (.contexts | path_errors($entry; $nodes))
    end;

# The refusals of one live step against the tree given, as it stands when the step runs.
def step_problems($s; $entry; $nodes):
  if ($s | type) != "object" then problem($entry; "must be an object")
  elif ($s.path | type) != "string" or ($s.path | split("/") | any(.[]; name_ok | not)) then
    problem($entry; "path must be a context path, such as share/psyops")
  elif $s.op == "create" then
    ($s | unknown_keys(["op", "path", "filter"]; $entry)),
    ($s.path | dirname) as $parent
    | if $parent == "" then problem($entry; "path must name the new context under a context")
      else
        (if $nodes[$parent] == null then
           problem($entry; "parent \($parent) does not exist at this step")
         elif $nodes[$parent] == "query" then
           problem($entry; "parent \($parent) is a query context; create under an explicit one")
         else empty end),
        (if $nodes[$s.path] != null then
           problem($entry; "\($s.path) already exists at this step; choose a free name")
         else empty end),
        (if $s | has("filter") then $s.filter | filter_errors($entry) else empty end)
      end
  elif $nodes[$s.path] == null then
    problem($entry; "\($s.path) does not exist at this step")
  elif $s.op == "rename" then
    ($s | unknown_keys(["op", "path", "name"]; $entry)),
    (if $s.name | name_ok | not then problem($entry; "name must be a non-empty string without /")
     elif $nodes[$s.path | dirname | under($s.name)] != null then
       problem($entry; "\($s.name) is taken among its siblings at this step; choose a free name")
     else empty end)
  elif $s.op == "move" then
    ($s | unknown_keys(["op", "path", "parent", "name"]; $entry)),
    (if ($s | has("name")) and ($s.name | name_ok | not) then
       problem($entry; "name must be a non-empty string without /")
     elif ($s.parent | type) != "string" or $nodes[$s.parent] == null then
       problem($entry; "parent \($s.parent | tojson) does not exist at this step")
     elif $nodes[$s.parent] == "query" then
       problem($entry; "parent \($s.parent) is a query context; move under an explicit one")
     elif $s.parent == $s.path or ($s.parent | startswith($s.path + "/")) then
       problem($entry; "parent \($s.parent) is inside \($s.path); move it elsewhere")
     elif $nodes[$s.parent | under($s.name // ($s.path | split("/") | last))] != null then
       problem($entry; "\($s.name // ($s.path | split("/") | last)) is taken under \($s.parent)"
         + " at this step; choose a free name")
     else empty end)
  else problem($entry; "op must be create, rename, or move")
  end;

# The tree given, the input, with the context at the old path and its subtree at the new path.
def relocate($old; $new):
  with_entries(if .key == $old or (.key | startswith($old + "/")) then
    .key = $new + .key[($old | length):]
  else . end);

# The refusals of the live steps, each against the tree as the steps before it left it, from the
# declared contexts given; a refused step leaves the tree as it was.
def step_errors($nodes):
  reduce (list("live_steps") | to_entries[]) as {key: $i, value: $s} ({nodes: $nodes, errors: []};
    "live_steps[\($i)]"
    + (if ($s | type) == "object" and ($s.op | type) == "string" and ($s.path | type) == "string"
       then " (\($s.op) \($s.path))" else "" end) as $entry
    | [step_problems($s; $entry; .nodes)] as $found
    | if $found != [] then .errors += $found
      elif $s.op == "create" then
        .nodes[$s.path] = (if $s | has("filter") then "query" else "explicit" end)
      elif $s.op == "rename" then
        .nodes |= relocate($s.path; $s.path | dirname | under($s.name))
      else
        .nodes |= relocate($s.path; $s.parent | under($s.name // ($s.path | split("/") | last)))
      end)
  | .errors[];

# Every refusal of the definition, the input, but its record bodies, which lib/tree.sh checks.
def tree_errors:
  if type != "object" then
    problem("definition"; "must be a JSON object of contexts, files, records, and live_steps")
  else
    unknown_keys(["contexts", "files", "records", "live_steps"]; "definition"),
    (if (.contexts | type) != "array" or (.contexts | length) == 0 then
       problem("definition"; "contexts must be a non-empty list of the top-level contexts")
     else .contexts | context_errors([]) end),
    (. as $definition | ("files", "records", "live_steps")
     | select(. as $key | $definition | has($key) and (.[$key] | type) != "array")
     | problem("definition"; "\(.) must be a list")),
    (declared as $nodes | [list("files")[] | objects | .id | strings] as $file_ids
     | (list("files") | to_entries[] | .key as $i | .value | file_errors($i; $nodes; $file_ids)),
       (list("records") | to_entries[] | .key as $i | .value
        | record_errors($i; $nodes; $file_ids)),
       ([(list("files"), list("records"))[] | objects | .id | strings] | group_by(.)[]
        | select(length > 1)
        | problem("id \(.[0])"; "\(length) entries share the id \(.[0]); give each its own")),
       step_errors($nodes))
  end;

# The ids of the definition's records whose bodies lib/tree.sh checks: each well-formed id once.
def record_ids:
  if type == "object" then
    [list("records")[] | objects | .id | strings | select(test(id_pattern))] | unique
  else [] end;

# The definition's one-line summary: its contexts, files, records, and live steps.
def tree_summary:
  "\(declared | length) contexts, \(list("files") | length) files,"
  + " \(list("records") | length) records, \(list("live_steps") | length) live steps";

# The declared contexts under the path given, as a list of names, each before its children, as
# {path, parent, name, kind, filter}: parent is the path above, empty at the top, and filter is
# null on an explicit context.
def load_nodes($prefix):
  if type == "array" then
    .[] | objects | select(.name | name_ok) | ($prefix + [.name]) as $path
    | {path: ($path | join("/")), parent: ($prefix | join("/")), name,
       kind: (if has("filter") then "query" else "explicit" end), filter: (.filter // null)},
      (select(has("filter") | not) | .contexts | load_nodes($path))
  else empty end;

# The rows of the load, one a declared context in load_nodes's order: its path, parent path, name,
# kind, and filter as JSON, separated by the unit separator, \u001f.
def load_rows:
  .contexts | load_nodes([]) | [.path, .parent, .name, .kind, (.filter | tojson)] | join("\u001f");

# The input filter in one form for every filter of the same conditions: each condition without a
# null value, an in's values sorted and unique, and the conditions sorted and unique.
def filter_form:
  if type == "array" then
    map(objects | with_entries(select(.value != null))
        | if .op == "in" and (.value | type) == "array" then .value |= unique else . end)
    | unique
  else . end;

# How the input context, as Mikoshi reads it, differs from the kind and filter the definition
# declares for it: empty when it doesn't, otherwise what it is and what the definition declares.
def context_difference($kind; $filter):
  if .kind != $kind then
    "exists with kind \(.kind), the definition declares kind \($kind)"
  elif (.filter | filter_form) != ($filter | filter_form) then
    "exists with filter \(.filter | tojson), the definition declares \($filter | tojson)"
  else empty end;
