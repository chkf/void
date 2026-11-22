#pragma once
#include <fcntl.h>
#include "VoidGit.h"

// Swift cannot portably call the variadic form of openat. These accesses never create files.
static inline int VoidOpenReadChild(int parent, const char *name, int flags) {
    return openat(parent, name, flags);
}
