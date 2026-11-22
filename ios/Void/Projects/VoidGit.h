#pragma once
#include <stddef.h>

// Commit buffers have room for a hexadecimal object ID and its terminating NUL.
enum { VoidGitIDSize = 65 };
int VoidGitClone(const char *url, const char *destination, char *commit, char *error, size_t size);
int VoidGitFetch(const char *database, const char *current, char *target, char *error, size_t size);
int VoidGitCheckout(const char *database, const char *worktree, const char *current,
                    const char *target, char *error, size_t size);
