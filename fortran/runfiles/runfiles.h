/**
 * @file runfiles.h
 * @brief Runfiles lookup library for Bazel-built Fortran binaries and tests.
 *
 * This is the C implementation backing the Fortran @c runfiles module.
 * The algorithm is ported from rules_cc//cc/runfiles/runfiles.cc.
 *
 * Users should not include this header directly; use the Fortran module
 * @c runfiles instead.
 */

#ifndef RULES_FORTRAN_FORTRAN_RUNFILES_RUNFILES_H_
#define RULES_FORTRAN_FORTRAN_RUNFILES_RUNFILES_H_

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Opaque handle to runfiles state. */
typedef struct rf_runfiles rf_runfiles;

/**
 * @brief Create a Runfiles instance for use from fortran_binary rules.
 *
 * Reads the @c RUNFILES_MANIFEST_FILE and @c RUNFILES_DIR environment
 * variables.  Falls back to argv0-based discovery if the env vars are
 * not set.
 *
 * @param argv0          The program path (argv[0]), or NULL / "" if unknown.
 * @param error_buf      Buffer for an error message on failure (may be NULL).
 * @param error_buf_len  Size of @p error_buf in bytes.
 * @return A new handle on success (caller must call rf_free()),
 *         or NULL on error.
 */
rf_runfiles* rf_create(const char* argv0, char* error_buf, int error_buf_len);

/**
 * @brief Create a Runfiles instance for use from fortran_test rules.
 *
 * Reads the @c RUNFILES_MANIFEST_FILE and @c TEST_SRCDIR environment
 * variables.
 *
 * @param error_buf      Buffer for an error message on failure (may be NULL).
 * @param error_buf_len  Size of @p error_buf in bytes.
 * @return A new handle on success (caller must call rf_free()),
 *         or NULL on error.
 */
rf_runfiles* rf_create_for_test(char* error_buf, int error_buf_len);

/**
 * @brief Resolve the runtime path of a runfile.
 *
 * @p path must be a non-empty runfiles-root-relative path without
 * uplevel references ("..") or self-references (".").  Absolute paths
 * are returned as-is.
 *
 * @param rf              The runfiles handle.
 * @param path            Runfiles-root-relative path to look up.
 * @param result_buf      Buffer for the resolved path (null-terminated).
 * @param result_buf_len  Size of @p result_buf in bytes.
 * @return The length of the resolved path (excluding null terminator),
 *         0 if not found (result_buf set to ""),
 *         or -1 on error (invalid path, NULL args, buffer too small).
 */
int rf_rlocation(const rf_runfiles* rf, const char* path, char* result_buf,
                 int result_buf_len);

/**
 * @brief Return the number of environment variable pairs for subprocesses.
 *
 * Subprocesses that also need runfiles access should have these variables
 * set in their environment.
 *
 * @param rf  The runfiles handle.
 * @return Number of key-value pairs (currently 3), or 0 if @p rf is NULL.
 */
int rf_env_vars_count(const rf_runfiles* rf);

/**
 * @brief Retrieve the @p index-th environment variable key-value pair.
 *
 * @param rf            The runfiles handle.
 * @param index         0-based index (must be < rf_env_vars_count()).
 * @param key_buf       Buffer for the variable name (null-terminated).
 * @param key_buf_len   Size of @p key_buf in bytes.
 * @param val_buf       Buffer for the variable value (null-terminated).
 * @param val_buf_len   Size of @p val_buf in bytes.
 * @return 1 on success, 0 if index is out of range or buffers are too small.
 */
int rf_env_var(const rf_runfiles* rf, int index, char* key_buf, int key_buf_len,
               char* val_buf, int val_buf_len);

/**
 * @brief Free a Runfiles instance.
 * @param rf  The handle to free, or NULL (no-op).
 */
void rf_free(rf_runfiles* rf);

#ifdef __cplusplus
}
#endif

#endif  // RULES_FORTRAN_FORTRAN_RUNFILES_RUNFILES_H_
