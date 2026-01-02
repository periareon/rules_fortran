/**
 * @file runfiles.c
 * @brief Runfiles lookup library -- C implementation.
 *
 * Ported from `@rules_cc//cc/runfiles/runfiles.cc`.
 */

#include "runfiles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#endif

/** @brief Maximum length of a single line in a runfiles manifest. */
#define RF_MAX_LINE 8192

/** @brief Initial capacity for the manifest key/value arrays. */
#define RF_INITIAL_CAPACITY 256

/** @brief Number of environment variables exposed for subprocesses. */
#define RF_NUM_ENV_VARS 3

/* ----------------------------------------------------------------------- */
/* Internal helpers: strings                                               */
/* ----------------------------------------------------------------------- */

/**
 * @brief Duplicate a string, returning a newly allocated copy.
 * @param s  The null-terminated source string, or NULL.
 * @return   A malloc'd copy, or NULL if @p s is NULL or allocation fails.
 */
static char* rf_strdup(const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char* copy = (char*)malloc(len + 1);
    if (copy) memcpy(copy, s, len + 1);
    return copy;
}

/**
 * @brief Concatenate two strings into a newly allocated buffer.
 * @param a  First string.
 * @param b  Second string.
 * @return   A malloc'd string containing @p a followed by @p b,
 *           or NULL on allocation failure.
 */
static char* rf_concat(const char* a, const char* b) {
    size_t la = strlen(a);
    size_t lb = strlen(b);
    char* result = (char*)malloc(la + lb + 1);
    if (result) {
        memcpy(result, a, la);
        memcpy(result + la, b, lb + 1);
    }
    return result;
}

/**
 * @brief Concatenate three strings into a newly allocated buffer.
 * @param a  First string.
 * @param b  Second string.
 * @param c  Third string.
 * @return   A malloc'd string containing @p a + @p b + @p c,
 *           or NULL on allocation failure.
 */
static char* rf_concat3(const char* a, const char* b, const char* c) {
    size_t la = strlen(a);
    size_t lb = strlen(b);
    size_t lc = strlen(c);
    char* result = (char*)malloc(la + lb + lc + 1);
    if (result) {
        memcpy(result, a, la);
        memcpy(result + la, b, lb);
        memcpy(result + la + lb, c, lc + 1);
    }
    return result;
}

/**
 * @brief Check whether @p s starts with @p prefix.
 * @return Non-zero if @p s begins with @p prefix, zero otherwise.
 */
static int rf_starts_with(const char* s, const char* prefix) {
    return strncmp(s, prefix, strlen(prefix)) == 0;
}

/**
 * @brief Check whether @p s ends with @p suffix.
 * @return Non-zero if @p s ends with @p suffix, zero otherwise.
 */
static int rf_ends_with(const char* s, const char* suffix) {
    size_t ls = strlen(s);
    size_t lsuf = strlen(suffix);
    if (ls < lsuf) return 0;
    return strcmp(s + ls - lsuf, suffix) == 0;
}

/**
 * @brief Check whether @p s contains @p substr.
 * @return Non-zero if @p substr appears anywhere in @p s, zero otherwise.
 */
static int rf_contains(const char* s, const char* substr) {
    return strstr(s, substr) != NULL;
}

/* ----------------------------------------------------------------------- */
/* Internal helpers: file system                                           */
/* ----------------------------------------------------------------------- */

/**
 * @brief Test whether @p path names a readable file.
 * @param path  Null-terminated file path.
 * @return 1 if the file can be opened for reading, 0 otherwise.
 */
static int rf_is_readable_file(const char* path) {
    FILE* f = fopen(path, "r");
    if (f) {
        fclose(f);
        return 1;
    }
    return 0;
}

/**
 * @brief Test whether @p path names an existing directory.
 * @param path  Null-terminated path.
 * @return 1 if the path is a directory, 0 otherwise.
 *
 * Uses GetFileAttributesA on Windows, stat() on POSIX.
 */
static int rf_is_directory(const char* path) {
#ifdef _WIN32
    DWORD attrs = GetFileAttributesA(path);
    return (attrs != INVALID_FILE_ATTRIBUTES) &&
           (attrs & FILE_ATTRIBUTE_DIRECTORY);
#else
    struct stat buf;
    return stat(path, &buf) == 0 && S_ISDIR(buf.st_mode);
#endif
}

/**
 * @brief Test whether @p path is an absolute path.
 *
 * Recognises Unix absolute paths (leading '/') and Windows absolute paths
 * (drive letter followed by ':' and '\\' or '/').  Drive-less absolute
 * paths on Windows (e.g. "\\foo") are *not* treated as absolute.
 *
 * @param path  Null-terminated path, or NULL.
 * @return 1 if absolute, 0 otherwise.
 */
static int rf_is_absolute(const char* path) {
    if (!path || !path[0]) return 0;
    char c = path[0];
    size_t len = strlen(path);
    if (c == '/' && (len < 2 || path[1] != '/')) return 1;
    if (len >= 3 && ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) &&
        path[1] == ':' && (path[2] == '\\' || path[2] == '/'))
        return 1;
    return 0;
}

/**
 * @brief Retrieve the value of an environment variable.
 * @param key  The variable name.
 * @return Pointer to the value (owned by the environment), or NULL if unset.
 */
static const char* rf_getenv(const char* key) { return getenv(key); }

/* ----------------------------------------------------------------------- */
/* Internal helpers: manifest unescape                                     */
/* ----------------------------------------------------------------------- */

/**
 * @brief Unescape a manifest entry according to the rules_cc convention.
 *
 * Recognised escape sequences (matching rules_cc):
 *   - @c \\s  -> space
 *   - @c \\n  -> newline
 *   - @c \\b  -> backslash
 *
 * @param s    Source buffer (not necessarily null-terminated).
 * @param len  Number of bytes to process from @p s.
 * @return A newly allocated null-terminated string with escapes resolved,
 *         or NULL on allocation failure.
 */
static char* rf_unescape(const char* s, size_t len) {
    char* result = (char*)malloc(len + 1);
    if (!result) return NULL;
    size_t j = 0;
    for (size_t i = 0; i < len; ++i) {
        if (s[i] == '\\' && i + 1 < len) {
            switch (s[i + 1]) {
                case 's':
                    result[j++] = ' ';
                    ++i;
                    break;
                case 'n':
                    result[j++] = '\n';
                    ++i;
                    break;
                case 'b':
                    result[j++] = '\\';
                    ++i;
                    break;
                default:
                    result[j++] = s[i];
                    result[j++] = s[i + 1];
                    ++i;
                    break;
            }
        } else {
            result[j++] = s[i];
        }
    }
    result[j] = '\0';
    return result;
}

/* ----------------------------------------------------------------------- */
/* Runfiles struct definition                                              */
/* ----------------------------------------------------------------------- */

/**
 * @brief Internal runfiles state.
 *
 * Holds the runfiles directory path and/or a parsed manifest
 * (sorted key/value arrays for binary search), plus the environment
 * variables that should be propagated to subprocesses.
 */
struct rf_runfiles {
    char* directory;                   /**< Runfiles directory, or "". */
    char* manifest_file;               /**< Manifest file path, or "". */
    char** keys;                       /**< Sorted manifest keys. */
    char** values;                     /**< Manifest values (parallel). */
    int num_entries;                   /**< Number of manifest entries. */
    int capacity;                      /**< Allocated capacity. */
    char* env_keys[RF_NUM_ENV_VARS];   /**< Subprocess env var names. */
    char* env_values[RF_NUM_ENV_VARS]; /**< Subprocess env var values. */
};

/* ----------------------------------------------------------------------- */
/* Manifest: sorted array with binary search                               */
/* ----------------------------------------------------------------------- */

/**
 * @brief Global pointer used by rf_index_compare during qsort.
 *
 * Set immediately before each qsort call in rf_sort_entries.
 * Not thread-safe; runfiles creation is expected to be single-threaded.
 */
static const char** rf_sort_keys_ptr;

/**
 * @brief qsort comparator that orders indices by their corresponding key.
 * @param a  Pointer to the first index (int).
 * @param b  Pointer to the second index (int).
 * @return   strcmp result on the keys at those indices.
 */
static int rf_index_compare(const void* a, const void* b) {
    int ia = *(const int*)a;
    int ib = *(const int*)b;
    return strcmp(rf_sort_keys_ptr[ia], rf_sort_keys_ptr[ib]);
}

/**
 * @brief Sort the manifest entries in @p rf by key.
 *
 * Uses an index-based sort so that the parallel key and value arrays
 * stay synchronised.  After sorting, binary search can be used for
 * O(log n) lookups.
 *
 * @param rf  The runfiles handle whose entries should be sorted.
 */
static void rf_sort_entries(rf_runfiles* rf) {
    if (rf->num_entries <= 1) return;

    int n = rf->num_entries;
    int* indices = (int*)malloc(sizeof(int) * n);
    if (!indices) return;
    for (int i = 0; i < n; i++) indices[i] = i;

    rf_sort_keys_ptr = (const char**)rf->keys;
    qsort(indices, n, sizeof(int), rf_index_compare);

    char** new_keys = (char**)malloc(sizeof(char*) * rf->capacity);
    char** new_values = (char**)malloc(sizeof(char*) * rf->capacity);
    if (!new_keys || !new_values) {
        free(indices);
        free(new_keys);
        free(new_values);
        return;
    }

    for (int i = 0; i < n; i++) {
        new_keys[i] = rf->keys[indices[i]];
        new_values[i] = rf->values[indices[i]];
    }

    free(rf->keys);
    free(rf->values);
    rf->keys = new_keys;
    rf->values = new_values;
    free(indices);
}

/**
 * @brief Search for @p key in the sorted manifest of @p rf.
 * @param rf   The runfiles handle.
 * @param key  The manifest key to look up.
 * @return     The index of the matching entry, or -1 if not found.
 */
static int rf_binary_search(const rf_runfiles* rf, const char* key) {
    int lo = 0, hi = rf->num_entries - 1;
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        int cmp = strcmp(rf->keys[mid], key);
        if (cmp == 0) return mid;
        if (cmp < 0)
            lo = mid + 1;
        else
            hi = mid - 1;
    }
    return -1;
}

/* ----------------------------------------------------------------------- */
/* Manifest parsing                                                        */
/* ----------------------------------------------------------------------- */

/**
 * @brief Append a key/value entry to the manifest arrays, growing if needed.
 * @param rf     The runfiles handle.
 * @param key    Heap-allocated key (ownership transferred on success).
 * @param value  Heap-allocated value (ownership transferred on success).
 * @return 1 on success, 0 on allocation failure.
 */
static int rf_add_entry(rf_runfiles* rf, char* key, char* value) {
    if (rf->num_entries >= rf->capacity) {
        int new_cap = rf->capacity * 2;
        char** new_keys = (char**)realloc(rf->keys, sizeof(char*) * new_cap);
        char** new_values =
            (char**)realloc(rf->values, sizeof(char*) * new_cap);
        if (!new_keys || !new_values) return 0;
        rf->keys = new_keys;
        rf->values = new_values;
        rf->capacity = new_cap;
    }
    rf->keys[rf->num_entries] = key;
    rf->values[rf->num_entries] = value;
    rf->num_entries++;
    return 1;
}

/**
 * @brief Parse a runfiles manifest file into sorted key/value arrays.
 *
 * Each non-empty line in the manifest has the form "key value" (separated
 * by a single space).  Lines beginning with a space use the escaped key
 * format defined in rf_unescape().
 *
 * After parsing, the entries are sorted by key via rf_sort_entries()
 * so that rf_binary_search() can be used for lookups.
 *
 * @param path       Path to the manifest file.
 * @param rf         The runfiles handle to populate.
 * @param error_buf  Buffer for an error message (may be NULL).
 * @param error_buf_len  Size of @p error_buf.
 * @return 1 on success, 0 on error.
 */
static int rf_parse_manifest(const char* path, rf_runfiles* rf, char* error_buf,
                             int error_buf_len) {
    FILE* f = fopen(path, "r");
    if (!f) {
        if (error_buf && error_buf_len > 0) {
            snprintf(error_buf, error_buf_len,
                     "ERROR: cannot open runfiles manifest \"%s\"", path);
        }
        return 0;
    }

    char line[RF_MAX_LINE];
    int line_count = 0;
    while (fgets(line, sizeof(line), f)) {
        line_count++;
        size_t len = strlen(line);
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
            line[--len] = '\0';
        }
        if (len == 0) continue;

        char* source;
        char* target;

        if (line[0] == ' ') {
            const char* space = strchr(line + 1, ' ');
            if (!space) {
                if (error_buf && error_buf_len > 0) {
                    snprintf(
                        error_buf, error_buf_len,
                        "ERROR: bad runfiles manifest entry in \"%s\" line #%d",
                        path, line_count);
                }
                fclose(f);
                return 0;
            }
            size_t key_len = space - (line + 1);
            source = rf_unescape(line + 1, key_len);
            target = rf_unescape(space + 1, len - (space - line) - 1);
        } else {
            const char* space = strchr(line, ' ');
            if (!space) {
                if (error_buf && error_buf_len > 0) {
                    snprintf(
                        error_buf, error_buf_len,
                        "ERROR: bad runfiles manifest entry in \"%s\" line #%d",
                        path, line_count);
                }
                fclose(f);
                return 0;
            }
            size_t key_len = space - line;
            source = (char*)malloc(key_len + 1);
            if (source) {
                memcpy(source, line, key_len);
                source[key_len] = '\0';
            }
            target = rf_strdup(space + 1);
        }

        if (!source || !target) {
            free(source);
            free(target);
            fclose(f);
            return 0;
        }

        if (!rf_add_entry(rf, source, target)) {
            free(source);
            free(target);
            fclose(f);
            return 0;
        }
    }

    fclose(f);
    rf_sort_entries(rf);
    return 1;
}

/* ----------------------------------------------------------------------- */
/* PathsFrom -- discover manifest and directory                            */
/* ----------------------------------------------------------------------- */

/**
 * @brief Discover the runfiles manifest and/or directory.
 *
 * Mirrors the PathsFrom logic in rules_cc:
 *  1. If @p mf_env / @p dir_env point to a valid manifest / directory,
 *     use them.
 *  2. Otherwise, try argv0-based discovery:
 *       - argv0.runfiles/MANIFEST  +  argv0.runfiles
 *       - argv0.runfiles_manifest
 *  3. If only one of manifest / directory is found, try to derive the other:
 *       - directory -> dir/MANIFEST  or  dir_manifest
 *       - manifest  -> strip "_manifest" or "/MANIFEST" to get directory
 *
 * @param argv0          Program path (may be "" or NULL).
 * @param mf_env         Value of RUNFILES_MANIFEST_FILE (may be "" or NULL).
 * @param dir_env        Value of RUNFILES_DIR or TEST_SRCDIR (may be "").
 * @param[out] out_manifest   Set to a malloc'd manifest path, or NULL.
 * @param[out] out_directory  Set to a malloc'd directory path, or NULL.
 * @return 1 if at least one of manifest/directory was found, 0 otherwise.
 */
static int rf_paths_from(const char* argv0, const char* mf_env,
                         const char* dir_env, char** out_manifest,
                         char** out_directory) {
    char* mf = mf_env && mf_env[0] ? rf_strdup(mf_env) : rf_strdup("");
    char* dir = dir_env && dir_env[0] ? rf_strdup(dir_env) : rf_strdup("");
    if (!mf || !dir) {
        free(mf);
        free(dir);
        return 0;
    }

    int mf_valid = mf[0] && rf_is_readable_file(mf);
    int dir_valid = dir[0] && rf_is_directory(dir);

    if (argv0 && argv0[0] && !mf_valid && !dir_valid) {
        free(mf);
        free(dir);
        mf = rf_concat(argv0, ".runfiles/MANIFEST");
        dir = rf_concat(argv0, ".runfiles");
        if (!mf || !dir) {
            free(mf);
            free(dir);
            return 0;
        }
        mf_valid = rf_is_readable_file(mf);
        dir_valid = rf_is_directory(dir);
        if (!mf_valid) {
            free(mf);
            mf = rf_concat(argv0, ".runfiles_manifest");
            if (!mf) {
                free(dir);
                return 0;
            }
            mf_valid = rf_is_readable_file(mf);
        }
    }

    if (!mf_valid && !dir_valid) {
        free(mf);
        free(dir);
        return 0;
    }

    if (!mf_valid && dir_valid) {
        free(mf);
        mf = rf_concat(dir, "/MANIFEST");
        if (mf) mf_valid = rf_is_readable_file(mf);
        if (!mf_valid) {
            free(mf);
            mf = rf_concat(dir, "_manifest");
            if (mf) mf_valid = rf_is_readable_file(mf);
        }
    }

    if (!dir_valid && mf_valid) {
        if (rf_ends_with(mf, ".runfiles_manifest") ||
            rf_ends_with(mf, "/MANIFEST")) {
            size_t mf_len = strlen(mf);
            free(dir);
            dir = (char*)malloc(mf_len - 9 + 1);
            if (dir) {
                memcpy(dir, mf, mf_len - 9);
                dir[mf_len - 9] = '\0';
                dir_valid = rf_is_directory(dir);
            }
        }
    }

    *out_manifest = mf_valid ? mf : NULL;
    *out_directory = dir_valid ? dir : NULL;

    if (!mf_valid) free(mf);
    if (!dir_valid) free(dir);

    return 1;
}

/* ----------------------------------------------------------------------- */
/* RlocationUnchecked                                                      */
/* ----------------------------------------------------------------------- */

/**
 * @brief Resolve a runfile path without input validation.
 *
 * Looks up @p path using three strategies in order:
 *  1. Exact match via binary search in the manifest.
 *  2. Longest-prefix match in the manifest (handles directory entries
 *     whose children are not individually listed).
 *  3. Directory-based fallback: directory + "/" + path.
 *
 * @param rf    The runfiles handle.
 * @param path  Runfiles-root-relative path (assumed valid).
 * @return A newly allocated resolved path, or NULL if not found.
 *         The caller must free() the returned string.
 */
static char* rf_rlocation_unchecked(const rf_runfiles* rf, const char* path) {
    int idx = rf_binary_search(rf, path);
    if (idx >= 0) {
        return rf_strdup(rf->values[idx]);
    }

    if (rf->num_entries > 0) {
        size_t path_len = strlen(path);
        size_t prefix_end = path_len;
        while (prefix_end > 0) {
            size_t i = prefix_end;
            while (i > 0 && path[i - 1] != '/') i--;
            if (i == 0) break;
            prefix_end = i - 1;

            char saved = ((char*)path)[prefix_end];
            ((char*)path)[prefix_end] = '\0';
            idx = rf_binary_search(rf, path);
            ((char*)path)[prefix_end] = saved;

            if (idx >= 0) {
                return rf_concat3(rf->values[idx], "/", path + prefix_end + 1);
            }
        }
    }

    if (rf->directory && rf->directory[0]) {
        return rf_concat3(rf->directory, "/", path);
    }

    return NULL;
}

/* ----------------------------------------------------------------------- */
/* Internal: rf_create_internal                                            */
/* ----------------------------------------------------------------------- */

/**
 * @brief Shared factory for rf_create() and rf_create_for_test().
 *
 * Discovers the manifest / directory via rf_paths_from(), parses the
 * manifest if present, and populates the subprocess environment variables.
 *
 * @param argv0          Program path ("" if unknown).
 * @param mf_env         Manifest file env var value ("" if unset).
 * @param dir_env        Directory env var value ("" if unset).
 * @param error_buf      Buffer for error messages (may be NULL).
 * @param error_buf_len  Size of @p error_buf.
 * @return A new rf_runfiles handle, or NULL on error.
 */
static rf_runfiles* rf_create_internal(const char* argv0, const char* mf_env,
                                       const char* dir_env, char* error_buf,
                                       int error_buf_len) {
    char* manifest = NULL;
    char* directory = NULL;

    if (!rf_paths_from(argv0 ? argv0 : "", mf_env, dir_env, &manifest,
                       &directory)) {
        if (error_buf && error_buf_len > 0) {
            snprintf(error_buf, error_buf_len,
                     "ERROR: cannot find runfiles (argv0=\"%s\")",
                     argv0 ? argv0 : "");
        }
        return NULL;
    }

    rf_runfiles* rf = (rf_runfiles*)calloc(1, sizeof(rf_runfiles));
    if (!rf) {
        free(manifest);
        free(directory);
        return NULL;
    }

    rf->directory = directory ? directory : rf_strdup("");
    rf->manifest_file = manifest ? manifest : rf_strdup("");
    rf->capacity = RF_INITIAL_CAPACITY;
    rf->keys = (char**)calloc(rf->capacity, sizeof(char*));
    rf->values = (char**)calloc(rf->capacity, sizeof(char*));
    rf->num_entries = 0;

    if (!rf->keys || !rf->values) {
        rf_free(rf);
        return NULL;
    }

    if (manifest && manifest[0]) {
        if (!rf_parse_manifest(manifest, rf, error_buf, error_buf_len)) {
            rf_free(rf);
            return NULL;
        }
    }

    rf->env_keys[0] = rf_strdup("RUNFILES_MANIFEST_FILE");
    rf->env_values[0] = rf_strdup(rf->manifest_file ? rf->manifest_file : "");
    rf->env_keys[1] = rf_strdup("RUNFILES_DIR");
    rf->env_values[1] = rf_strdup(rf->directory ? rf->directory : "");
    rf->env_keys[2] = rf_strdup("JAVA_RUNFILES");
    rf->env_values[2] = rf_strdup(rf->directory ? rf->directory : "");

    return rf;
}

/* ----------------------------------------------------------------------- */
/* Public API                                                              */
/* ----------------------------------------------------------------------- */

/** @copydoc rf_create */
rf_runfiles* rf_create(const char* argv0, char* error_buf, int error_buf_len) {
    const char* mf_env = rf_getenv("RUNFILES_MANIFEST_FILE");
    const char* dir_env = rf_getenv("RUNFILES_DIR");
    return rf_create_internal(argv0, mf_env ? mf_env : "",
                              dir_env ? dir_env : "", error_buf, error_buf_len);
}

/** @copydoc rf_create_for_test */
rf_runfiles* rf_create_for_test(char* error_buf, int error_buf_len) {
    const char* mf_env = rf_getenv("RUNFILES_MANIFEST_FILE");
    const char* dir_env = rf_getenv("TEST_SRCDIR");
    return rf_create_internal("", mf_env ? mf_env : "", dir_env ? dir_env : "",
                              error_buf, error_buf_len);
}

/** @copydoc rf_rlocation */
int rf_rlocation(const rf_runfiles* rf, const char* path, char* result_buf,
                 int result_buf_len) {
    if (!rf || !path || !result_buf || result_buf_len <= 0) return -1;

    result_buf[0] = '\0';

    size_t path_len = strlen(path);
    if (path_len == 0) return -1;
    if (rf_starts_with(path, "../") || rf_contains(path, "/..") ||
        rf_starts_with(path, "./") || rf_contains(path, "/./") ||
        rf_ends_with(path, "/.") || rf_contains(path, "//")) {
        return -1;
    }

    if (rf_is_absolute(path)) {
        int len = (int)path_len;
        if (len + 1 > result_buf_len) return -1;
        memcpy(result_buf, path, len + 1);
        return len;
    }

    char* resolved = rf_rlocation_unchecked(rf, path);
    if (!resolved || !resolved[0]) {
        free(resolved);
        result_buf[0] = '\0';
        return 0;
    }

    int len = (int)strlen(resolved);
    if (len + 1 > result_buf_len) {
        free(resolved);
        return -1;
    }
    memcpy(result_buf, resolved, len + 1);
    free(resolved);
    return len;
}

/** @copydoc rf_env_vars_count */
int rf_env_vars_count(const rf_runfiles* rf) {
    if (!rf) return 0;
    return RF_NUM_ENV_VARS;
}

/** @copydoc rf_env_var */
int rf_env_var(const rf_runfiles* rf, int index, char* key_buf, int key_buf_len,
               char* val_buf, int val_buf_len) {
    if (!rf || index < 0 || index >= RF_NUM_ENV_VARS) return 0;
    if (!key_buf || key_buf_len <= 0 || !val_buf || val_buf_len <= 0) return 0;

    const char* key = rf->env_keys[index];
    const char* val = rf->env_values[index];
    if (!key || !val) return 0;

    int klen = (int)strlen(key);
    int vlen = (int)strlen(val);
    if (klen + 1 > key_buf_len || vlen + 1 > val_buf_len) return 0;

    memcpy(key_buf, key, klen + 1);
    memcpy(val_buf, val, vlen + 1);
    return 1;
}

/** @copydoc rf_free */
void rf_free(rf_runfiles* rf) {
    if (!rf) return;
    free(rf->directory);
    free(rf->manifest_file);
    for (int i = 0; i < rf->num_entries; i++) {
        free(rf->keys[i]);
        free(rf->values[i]);
    }
    free(rf->keys);
    free(rf->values);
    for (int i = 0; i < RF_NUM_ENV_VARS; i++) {
        free(rf->env_keys[i]);
        free(rf->env_values[i]);
    }
    free(rf);
}
