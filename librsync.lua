
--librsync 2 binding.
--Written by Cosmin Apreutesei. Public Domain.

if not ... then require'librsync_test'; return end

local ffi = require'ffi'
local C = ffi.load'rsync'
local M = {C = C}

ffi.cdef[[
typedef struct FILE FILE;

// librsync-config.h
typedef long long rs_long_t;

// librsync.h
char const rs_librsync_version[];
char const rs_licence_string[];

// error reporting
typedef enum rs_result {
    RS_DONE = 0,
    RS_BLOCKED = 1,
    RS_RUNNING = 2,
    RS_TEST_SKIPPED = 77,
    RS_IO_ERROR = 100,
    RS_SYNTAX_ERROR = 101,
    RS_MEM_ERROR = 102,
    RS_INPUT_ENDED = 103,
    RS_BAD_MAGIC = 104,
    RS_UNIMPLEMENTED = 105,
    RS_CORRUPT = 106,
    RS_INTERNAL_ERROR = 107,
    RS_PARAM_ERROR = 108
} rs_result;
char const *rs_strerror(rs_result r);

enum {
	RS_DEFAULT_BLOCK_LEN = 2048,
};

// signature buffers
typedef enum {
    RS_DELTA_MAGIC = 0x72730236,
    RS_MD4_SIG_MAGIC = 0x72730136,
    RS_BLAKE2_SIG_MAGIC = 0x72730137
} rs_magic_number;
const int RS_MD4_SUM_LENGTH, RS_BLAKE2_SUM_LENGTH;
typedef unsigned int rs_weak_sum_t;
typedef unsigned char rs_strong_sum_t[32];
typedef struct rs_signature rs_signature_t;
void rs_free_sumset(rs_signature_t *);
void rs_sumset_dump(rs_signature_t const *);

// push-style API
typedef struct rs_buffers_s {
    char *next_in;
    size_t avail_in;
    int eof_in;
    char *next_out;
    size_t avail_out;
} rs_buffers_t;
typedef struct rs_job rs_job_t;
rs_result rs_job_iter(rs_job_t *job, rs_buffers_t *buffers);
rs_result rs_job_free(rs_job_t *);
rs_job_t *rs_sig_begin(size_t new_block_len, size_t strong_sum_len, rs_magic_number sig_magic);
rs_job_t *rs_delta_begin(rs_signature_t *);
rs_job_t *rs_loadsig_begin(rs_signature_t **);
rs_result rs_build_hash_table(rs_signature_t* sums);
typedef rs_result rs_copy_cb(void *opaque, rs_long_t pos, size_t *len, void **buf);
rs_job_t *rs_patch_begin(rs_copy_cb *copy_cb, void *copy_arg);

// pull-style API (not used)
typedef rs_result rs_driven_cb(rs_job_t *job, rs_buffers_t *buf, void *opaque);
rs_result rs_job_drive(rs_job_t *job, rs_buffers_t *buf, rs_driven_cb in_cb, void *in_opaque, rs_driven_cb out_cb, void *out_opaque);

// FILE-based API (not used)
typedef struct rs_stats {
    char const *op;
    int lit_cmds;
    rs_long_t lit_bytes;
    rs_long_t lit_cmdbytes;
    rs_long_t copy_cmds, copy_bytes, copy_cmdbytes;
    rs_long_t sig_cmds, sig_bytes;
    int false_matches;
    rs_long_t sig_blocks;
    size_t block_len;
    rs_long_t in_bytes;
    rs_long_t out_bytes;
} rs_stats_t;
char *rs_format_stats(rs_stats_t const *stats, char *buf, size_t size);
int rs_log_stats(rs_stats_t const *stats);
const rs_stats_t * rs_job_statistics(rs_job_t *job);
rs_result rs_sig_file(FILE *old_file, FILE *sig_file, size_t block_len, size_t strong_len, rs_magic_number sig_magic, rs_stats_t *stats);
rs_result rs_loadsig_file(FILE *sig_file, rs_signature_t **sumset, rs_stats_t *stats);
rs_result rs_file_copy_cb(void *arg, rs_long_t pos, size_t *len, void **buf);
rs_result rs_delta_file(rs_signature_t *, FILE *new_file, FILE *delta_file, rs_stats_t *);
rs_result rs_patch_file(FILE *basis_file, FILE *delta_file, FILE *new_file, rs_stats_t *);

// tracing API (not used)
typedef enum {
    RS_LOG_EMERG = 0,
    RS_LOG_ALERT = 1,
    RS_LOG_CRIT = 2,
    RS_LOG_ERR = 3,
    RS_LOG_WARNING = 4,
    RS_LOG_NOTICE = 5,
    RS_LOG_INFO = 6,
    RS_LOG_DEBUG = 7
} rs_loglevel;
typedef void rs_trace_fn_t(rs_loglevel level, char const *msg);
void rs_trace_set_level(rs_loglevel level);
void rs_trace_to(rs_trace_fn_t *);
void rs_trace_stderr(rs_loglevel level, char const *msg);
int rs_supports_trace(void);
]]

function M.version()
	return ffi.string(C.rs_librsync_version)
end

local rs_loglevel = {
	emerg   = C.RS_LOG_EMERG,
	alert   = C.RS_LOG_ALERT,
	crit    = C.RS_LOG_CRIT,
	err     = C.RS_LOG_ERR,
	error   = C.RS_LOG_ERR,
	warn    = C.RS_LOG_WARNING,
	warning = C.RS_LOG_WARNING,
	notice  = C.RS_LOG_NOTICE,
	info    = C.RS_LOG_INFO,
	debug   = C.RS_LOG_DEBUG,
}
local trace_cb
local function free_trace_cb()
	if trace_cb then
		trace_cb:free()
		trace_cb = nil
	end
end
function M.trace(arg)
	if type(arg) == 'string' then
		C.rs_trace_set_level(assert(rs_loglevel[arg]))
	elseif type(arg) == 'function' then
		local function wrapper(level, msg)
			arg(level, ffi.string(msg))
		end
		free_trace_cb()
		trace_cb = ffi.cast('rs_trace_fn_t', wrapper)
		C.rs_trace_to(trace_cb)
	elseif arg == true then
		free_trace_cb()
		C.rs_trace_to(C.rs_trace_stderr)
	elseif arg == false then
		M.trace(function() end)
	elseif not arg then
		return C.rs_supports_trace() == 1
	end
end

function M.strerror(r)
	local s = C.rs_strerror(r)
	return s ~= nil and ffi.string(s) or nil
end

local function check(ret)
	if ret == C.RS_DONE then return end
	error(string.format('rsync error %d: %s', tonumber(ret), M.strerror(ret)))
end

local function job(job)
	assert(job ~= nil)
	ffi.gc(job, job.free)
	return job
end

function M.create_sig_job(block_len, strong_sum_len, magic)
	return job(C.rs_sig_begin(
		block_len or C.RS_DEFAULT_BLOCK_LEN,
		strong_sum_len or 0,
		magic or C.RS_BLAKE2_SIG_MAGIC))
end

function M.load_sig_job()
	local sigbuf = ffi.new'rs_signature_t*[1]'
	local job = job(C.rs_loadsig_begin(sigbuf))
	local sig = sigbuf[0]
	ffi.gc(sig, C.rs_free_sumset)
	return job, sig
end

function M.create_delta_job(sig)
	return job(C.rs_delta_begin(sig))
end

function M.patch_job(copy_cb, copy_arg)
	local job = C.rs_patch_begin(copy_cb, copy_arg)
end

local job = {}
job.__index = job

function job:next(buffers)
	local ret = C.rs_job_iter(self, buffers)
	if ret == C.RS_BLOCKED then return true end
	check(ret)
end

function job:free()
	ffi.gc(self, nil)
	assert(C.rs_job_free(self) == 0)
end

job.stats = C.rs_job_statistics

local buffers = {}
buffers.__index = buffers

function M.build_hash_table(sig)
	check(C.rs_build_hash_table(sig))
end

ffi.metatype('rs_job_t', job)
ffi.metatype('rs_buffers_t', buffers)

M.buffers = ffi.typeof'rs_buffers_t'

--[[
typedef struct rs_stats {
    char const *op;
    int lit_cmds;
    rs_long_t lit_bytes;
    rs_long_t lit_cmdbytes;
    rs_long_t copy_cmds, copy_bytes, copy_cmdbytes;
    rs_long_t sig_cmds, sig_bytes;
    int false_matches;
    rs_long_t sig_blocks;
    size_t block_len;
    rs_long_t in_bytes;
    rs_long_t out_bytes;
} rs_stats_t;
const int RS_MD4_SUM_LENGTH, RS_BLAKE2_SUM_LENGTH;
enum {
	RS_MAX_STRONG_SUM_LENGTH = 32,
};
typedef unsigned int rs_weak_sum_t;
typedef unsigned char rs_strong_sum_t[32];

char *rs_format_stats(rs_stats_t const *stats, char *buf, size_t size);
int rs_log_stats(rs_stats_t const *stats);

typedef struct rs_signature rs_signature_t;
void rs_free_sumset(rs_signature_t *);
void rs_sumset_dump(rs_signature_t const *);






rs_result rs_sig_file(FILE *old_file, FILE *sig_file,
                      size_t block_len, size_t strong_len,
              rs_magic_number sig_magic,
              rs_stats_t *stats);
rs_result rs_loadsig_file(FILE *sig_file, rs_signature_t **sumset,
    rs_stats_t *stats);
rs_result rs_file_copy_cb(void *arg, rs_long_t pos, size_t *len, void **buf);
rs_result rs_delta_file(rs_signature_t *, FILE *new_file, FILE *delta_file, rs_stats_t *);
rs_result rs_patch_file(FILE *basis_file, FILE *delta_file, FILE *new_file, rs_stats_t *);
]]

return M
