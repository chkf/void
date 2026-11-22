#include "VoidGit.h"
#if defined(__APPLE__) && defined(__clang__)
#pragma clang module import libgit2
#else
#include <git2.h>
#endif
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static pthread_once_t git_once = PTHREAD_ONCE_INIT;
static int initialization;

static void initialize(void) {
    initialization = git_libgit2_init();
    if (initialization >= 0) initialization = git_libgit2_opts(GIT_OPT_SET_SERVER_CONNECT_TIMEOUT, 15000);
    if (!initialization) initialization = git_libgit2_opts(GIT_OPT_SET_SERVER_TIMEOUT, 60000);
}

static int ready(void) {
    pthread_once(&git_once, initialize);
    return initialization;
}

static int finish(int result, char *message, size_t size) {
    if (result == GIT_EAUTH && !message[0]) {
        snprintf(message, size, "无法匿名访问仓库，请检查地址并确认仓库已公开。");
    } else if (result < 0 && !message[0]) {
        const git_error *detail = git_error_last();
        snprintf(message, size, "%s", detail && detail->message ? detail->message : "Git 操作失败");
    }
    return result;
}

int VoidGitClone(const char *url, const char *destination, char *commit, char *error, size_t size) {
    git_repository *repo = NULL;
    git_reference *head = NULL;
    git_clone_options options = GIT_CLONE_OPTIONS_INIT;
    options.fetch_opts.follow_redirects = GIT_REMOTE_REDIRECT_NONE;
    int result = ready();
    if (!result) result = git_clone(&repo, url, destination, &options);
    if (!result) result = git_repository_head(&head, repo);
    if (!result) git_oid_tostr(commit, VoidGitIDSize, git_reference_target(head));
    git_reference_free(head);
    git_repository_free(repo);
    return finish(result, error, size);
}

int VoidGitFetch(const char *database, const char *current, char *target, char *error, size_t size) {
    git_repository *repo = NULL;
    git_reference *branch = NULL;
    git_remote *remote = NULL;
    git_oid baseline;
    const git_remote_head **refs = NULL;
    size_t count = 0;
    git_fetch_options options = GIT_FETCH_OPTIONS_INIT;
    options.follow_redirects = GIT_REMOTE_REDIRECT_NONE;
    int result = ready();
    if (!result) result = git_repository_open(&repo, database);
    if (!result) result = git_oid_fromstr(&baseline, current);
    if (!result) result = git_repository_head(&branch, repo);
    if (!result) result = git_remote_lookup(&remote, repo, "origin");
    if (!result) result = git_remote_fetch(remote, NULL, &options, NULL);
    if (!result) result = git_remote_ls(&refs, &count, remote);
    if (!result) {
        const git_oid *tip = NULL;
        for (size_t i = 0; i < count; i++) {
            if (!strcmp(refs[i]->name, git_reference_name(branch))) { tip = &refs[i]->oid; break; }
        }
        if (!tip) {
            snprintf(error, size, "GitHub 上已找不到导入时的分支");
            result = GIT_ENOTFOUND;
        } else if (git_oid_equal(tip, &baseline)) {
            git_oid_tostr(target, VoidGitIDSize, tip);
        } else {
            int descendant = git_graph_descendant_of(repo, tip, &baseline);
            if (descendant > 0) git_oid_tostr(target, VoidGitIDSize, tip);
            else if (descendant < 0) result = descendant;
            else {
                snprintf(error, size, "远端分支的历史已改写，无法快进。当前项目已保留。");
                result = GIT_ENONFASTFORWARD;
            }
        }
    }
    git_remote_free(remote);
    git_reference_free(branch);
    git_repository_free(repo);
    return finish(result, error, size);
}

struct conflict_message { char *text; size_t size; };

static int conflict(git_checkout_notify_t why, const char *path, const git_diff_file *baseline,
                    const git_diff_file *target, const git_diff_file *workdir, void *payload) {
    (void)baseline;
    (void)target;
    (void)workdir;
    struct conflict_message *message = payload;
    if (why == GIT_CHECKOUT_NOTIFY_CONFLICT && !message->text[0])
        snprintf(message->text, message->size, "「%s」有本地修改，与远端更新冲突。请处理后再拉取。", path);
    return 0;
}

// Apply a fast-forward to a copy of the user's files, with the index reconstructed
// from the last published commit for every attempt.
int VoidGitCheckout(const char *database, const char *worktree, const char *current,
                    const char *target, char *error, size_t size) {
    git_repository *repo = NULL;
    git_index *index = NULL;
    git_oid current_oid, target_oid;
    git_commit *before = NULL, *after = NULL;
    git_tree *baseline = NULL;
    git_checkout_options options = GIT_CHECKOUT_OPTIONS_INIT;
    struct conflict_message message = { error, size };
    int result = ready();
    if (!result) result = git_repository_open(&repo, database);
    if (!result) result = git_repository_set_workdir(repo, worktree, 0);
    if (!result) result = git_oid_fromstr(&current_oid, current);
    if (!result) result = git_oid_fromstr(&target_oid, target);
    if (!result) result = git_commit_lookup(&before, repo, &current_oid);
    if (!result) result = git_commit_lookup(&after, repo, &target_oid);
    if (!result) result = git_commit_tree(&baseline, before);
    if (!result) result = git_repository_index(&index, repo);
    if (!result) result = git_index_read_tree(index, baseline);
    options.baseline = baseline;
    options.notify_flags = GIT_CHECKOUT_NOTIFY_CONFLICT;
    options.notify_cb = conflict;
    options.notify_payload = &message;
    options.checkout_strategy = GIT_CHECKOUT_SAFE | GIT_CHECKOUT_NO_REFRESH |
        GIT_CHECKOUT_DONT_UPDATE_INDEX | GIT_CHECKOUT_DONT_OVERWRITE_IGNORED;
    if (!result) result = git_checkout_tree(repo, (git_object *)after, &options);
    if (result == GIT_ECONFLICT && !error[0]) snprintf(error, size, "本地修改与远端更新冲突。请处理后再拉取。");
    git_tree_free(baseline);
    git_index_free(index);
    git_commit_free(before);
    git_commit_free(after);
    git_repository_free(repo);
    return finish(result, error, size);
}
