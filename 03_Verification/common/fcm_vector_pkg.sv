// File: fcm_vector_pkg.sv
// Description: Reads and parses shared reference vector files.

// Shared helpers for reading verification vectors. The package can be used by IP, SoC, and directed
// tests without a virtual interface.

// Package: fcm_vector_pkg
// Description: Keeps the related verification helpers together.
package fcm_vector_pkg;

  import fcm_pkg::*;

  // Use one default vector path for manual simulation runs.
  localparam string FCM_DEFAULT_VECTOR_DIR = "../../03_Verification/vectors/precision";

  // Read +FCM_VECTORS, or use the default vector path.
  // Function: fcm_vector_spec
  // Description: Handles vector spec for the vector files.
  function automatic string fcm_vector_spec();
    string spec;
    if (!$value$plusargs("FCM_VECTORS=%s", spec)) return FCM_DEFAULT_VECTOR_DIR;
    return spec;
  endfunction

  // Read +FCM_MAX_ITEMS; zero means all items.
  // Function: fcm_max_items
  // Description: Handles max items for the vector files.
  function automatic int unsigned fcm_max_items();
    int unsigned limit;
    if (!$value$plusargs("FCM_MAX_ITEMS=%d", limit)) return 0;
    return limit;
  endfunction

  // Split comma-separated vector paths so one simulation can use several cases.
  // Function: fcm_split_dirs
  // Description: Handles split dirs for the vector files.
  function automatic int fcm_split_dirs(string spec, ref string out[$]);
    int start_pos = 0;
    out.delete();
    for (int i = 0; i <= spec.len(); i++) begin
      if (i == spec.len() || spec[i] == ",") begin
        if (i > start_pos) out.push_back(spec.substr(start_pos, i - 1));
        start_pos = i + 1;
      end
    end
    return out.size();
  endfunction

  // Return the first vector directory for directed tests.
  // Function: fcm_vector_dir
  // Description: Handles vector dir for the vector files.
  function automatic string fcm_vector_dir();
    string dirs [$];
    if (fcm_split_dirs(fcm_vector_spec(), dirs) == 0) return FCM_DEFAULT_VECTOR_DIR;
    return dirs[0];
  endfunction

  // Read reference vectors directly from the generated case directories.

  // Read hexadecimal words from a .mem file and return the word count, or -1 on error.
  // Function: fcm_read_mem
  // Description: Reads read mem from the vector data.
  function automatic int fcm_read_mem(string path, ref longint unsigned values[$]);
    int fd;
    int code;
    longint unsigned word;

    values.delete();
    fd = $fopen(path, "r");
    if (fd == 0) return -1;
    forever begin
      code = $fscanf(fd, "%h", word);
      if (code != 1) break;
      values.push_back(word);
    end
    $fclose(fd);
    return values.size();
  endfunction

  // Read the required fields from vector_contract.txt and ignore other keys.
  // Function: fcm_read_contract
  // Description: Reads read contract from the vector data.
  function automatic bit fcm_read_contract(string path, ref int k, ref int iterations);
    int fd;
    int code;
    string tag;

    k = 0;
    iterations = 0;
    fd = $fopen(path, "r");
    if (fd == 0) return 1'b0;
    forever begin
      code = $fscanf(fd, "%s", tag);
      if (code != 1) break;
      if (tag == "K")               code = $fscanf(fd, "%d", k);
      else if (tag == "ITERATIONS") code = $fscanf(fd, "%d", iterations);
    end
    $fclose(fd);
    return (k != 0) && (iterations != 0);
  endfunction

  // Read flat JSON Lines trace values by field name without a full JSON parser.

  // Find the position after a JSON field name, or return -1.
  // Function: fcm_json_seek
  // Description: Parses the requested value from JSON trace text.
  function automatic int fcm_json_seek(string s, string key);
    string pat;
    int n, m;

    pat = {"\"", key, "\":"};
    n = s.len();
    m = pat.len();
    for (int i = 0; i + m <= n; i++)
      if (s.substr(i, i + m - 1) == pat) return i + m;
    return -1;
  endfunction

  // Read an unsigned integer and move past the parsed value.
  // Function: fcm_json_uint
  // Description: Parses the requested value from JSON trace text.
  function automatic longint unsigned fcm_json_uint(string s, ref int pos);
    longint unsigned v;
    byte c;

    v = 0;
    while (pos < s.len()) begin
      c = s.getc(pos);
      if (c != " " && c != ",") break;
      pos++;
    end
    while (pos < s.len()) begin
      c = s.getc(pos);
      if (c < "0" || c > "9") break;
      v = v * 10 + longint'(c - "0");
      pos++;
    end
    return v;
  endfunction

  // Read the unsigned integer array for a JSON field.
  // Function: fcm_json_uint_array
  // Description: Parses the requested value from JSON trace text.
  function automatic void fcm_json_uint_array(string s, string key,
                                              ref longint unsigned out[$]);
    int pos;
    // Use a variable name that does not conflict with a SystemVerilog keyword.
    int prev_pos;

    out.delete();
    pos = fcm_json_seek(s, key);
    if (pos < 0) return;
    if (s.getc(pos) != "[") return;
    pos++;
    while (pos < s.len() && s.getc(pos) != "]") begin
      prev_pos = pos;
      out.push_back(fcm_json_uint(s, pos));
      // Stop parsing if the input contains an unexpected character.
      if (pos == prev_pos) break;
    end
  endfunction

  // Read a numeric JSON field, returning zero if it is missing.
  // Function: fcm_json_uint_field
  // Description: Parses the requested value from JSON trace text.
  function automatic longint unsigned fcm_json_uint_field(string s, string key);
    int pos;

    pos = fcm_json_seek(s, key);
    if (pos < 0) return 0;
    return fcm_json_uint(s, pos);
  endfunction

  // Add leading zeros to case numbers; SystemVerilog width formatting pads with spaces.
  // Function: fcm_pad
  // Description: Handles pad for the vector files.
  function automatic string fcm_pad(int value, int width);
    string s;
    s = $sformatf("%0d", value);
    while (s.len() < width) s = {"0", s};
    return s;
  endfunction

  // Build a case path using the cluster count.
  // Function: fcm_case_dir
  // Description: Handles case dir for the vector files.
  function automatic string fcm_case_dir(string base, int k);
    return {base, "/demo_k", fcm_pad(k, 2)};
  endfunction

  // Build the per-iteration JSON Lines trace path.
  // Function: fcm_trace_path
  // Description: Handles trace path for the vector files.
  function automatic string fcm_trace_path(string case_dir, int iteration);
    return {case_dir, "/bin_traces/iter_", fcm_pad(iteration, 3),
            "_bin_trace.jsonl"};
  endfunction
endpackage
