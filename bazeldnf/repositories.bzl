"""Declare runtime dependencies

These are needed for local dev, and users must install them as well.
See https://docs.bazel.build/versions/main/skylark/deploying.html#dependencies
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file", _http_archive = "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//bazeldnf:platforms.bzl", "PLATFORMS")
load("//bazeldnf/private:toolchains_repo.bzl", "toolchains_repo")
load("//tools:integrity.bzl", "INTEGRITY")
load("//tools:version.bzl", "REPO_URL", "VERSION")

def http_archive(name, **kwargs):
    maybe(_http_archive, name = name, **kwargs)

# WARNING: any changes in this function may be BREAKING CHANGES for users
# because we'll fetch a dependency which may be different from one that
# they were previously fetching later in their WORKSPACE setup, and now
# ours took precedence. Such breakages are challenging for users, so any
# changes in this function should be marked as BREAKING in the commit message
# and released only in semver majors.
# This is all fixed by bzlmod, so we just tolerate it for now.
def bazeldnf_dependencies():
    http_archive(
        name = "bazel_skylib",
        sha256 = "bc283cdfcd526a52c3201279cda4bc298652efa898b10b4db0837dc51652756f",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.7.1/bazel-skylib-1.7.1.tar.gz",
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.7.1/bazel-skylib-1.7.1.tar.gz",
        ],
    )
    http_archive(
        name = "platforms",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/platforms/releases/download/0.0.10/platforms-0.0.10.tar.gz",
            "https://github.com/bazelbuild/platforms/releases/download/0.0.10/platforms-0.0.10.tar.gz",
        ],
        sha256 = "218efe8ee736d26a3572663b374a253c012b716d8af0c07e842e82f238a0a7ee",
    )

########
# Remaining content of the file is only used to support toolchains.
########
_DOC = "Fetch external tools needed for bazeldnf toolchain"
_ATTRS = {
    "tool": attr.string(mandatory = True),
}

def _bazeldnf_repo_impl(repository_ctx):
    build_content = """# Generated by bazeldnf/repositories.bzl
load("@bazeldnf//bazeldnf:toolchain.bzl", "bazeldnf_toolchain")

bazeldnf_toolchain(
    name = "bazeldnf_toolchain",
    tool = "@{0}//file",
)
""".format(
        repository_ctx.attr.tool,
    )

    # Base BUILD file for this repository
    repository_ctx.file("BUILD.bazel", build_content)

bazeldnf_repositories = repository_rule(
    _bazeldnf_repo_impl,
    doc = _DOC,
    attrs = _ATTRS,
)

# Wrapper macro around everything above, this is the primary API
def bazeldnf_register_toolchains(name, register = True, **kwargs):
    """Convenience macro for users which does typical setup.

    - create a repository for each built-in platform like "bazeldnf_linux_amd64" -
      this repository is lazily fetched when node is needed for that platform.
    - TODO: create a convenience repository for the host platform like "bazeldnf_host"
    - create a repository exposing toolchains for each platform like "bazeldnf_platforms"
    - register a toolchain pointing at each platform
    Users can avoid this macro and do these steps themselves, if they want more control.
    Args:
        name: base name for all created repos, like "bazeldnf1_14"
        register: whether to call through to native.register_toolchains.
            Should be True for WORKSPACE users, but false when used under bzlmod extension
        **kwargs: passed to each node_repositories call
    """
    for platform in PLATFORMS.keys():
        name_ = "prebuilt-%s-%s" % (name, platform)
        fname = "bazeldnf-{0}-{1}".format(
            VERSION,
            platform,
        )
        url = "https://github.com/{repo_url}/releases/download/{version}/{file_name}".format(
            file_name = fname,
            repo_url = REPO_URL,
            version = VERSION,
        )
        http_file(
            name = name_,
            sha256 = INTEGRITY[platform],
            executable = True,
            url = url,
        )
        bazeldnf_repositories(
            name = "%s_%s" % (name, platform),
            tool = name_,
            **kwargs
        )
        if register:
            native.register_toolchains("@%s_toolchains//:%s_toolchain" % (name, platform))

    toolchains_repo(
        name = name + "_toolchains",
        user_repository_name = name,
    )
