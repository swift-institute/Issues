# Restores the io_uring probe shape from swift-linux-standard@66fea99
# (replaced in 4a41a602 to avoid the StackNesting crash) in today's test file.
undef $/;
my $s = <STDIN>;
my $old = <<'SWIFT';
        do {
            _ = try Kernel.IO.Uring.setup(
                entries: Kernel.IO.Uring.Submission.Count(_unchecked: Cardinal(1)),
                params: &params
            )
            return true
        } catch Kernel.IO.Uring.Error.setup(let code) where code == .posix(EPERM) || code == .posix(ENOSYS) {
            return false
        }
SWIFT
my $n = ($s =~ s/        do \{\n            let descriptor = try Kernel\.IO\.Uring\.setup\(.*?\n            return false\n        \}\n/$old/s);
die "probe shape not found\n" unless $n == 1;
print $s;
