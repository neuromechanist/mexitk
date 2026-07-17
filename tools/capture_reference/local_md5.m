function h = local_md5(x)
% Compute an MD5 hex digest of the raw bytes of array x (any numeric class).
md = java.security.MessageDigest.getInstance('MD5');
bytes = typecast(x(:), 'uint8');
md.update(bytes);
digest = md.digest();
digest = mod(double(digest), 256); % Java int8 -> unsigned 0-255
h = lower(sprintf('%02x', digest));
end
