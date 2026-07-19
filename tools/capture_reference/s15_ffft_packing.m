% s15_ffft_packing: settle FFFT's per-mode output packing.
%
% FFFT's two captured mri fixtures (real0, complex1) could not be
% reproduced by any candidate transform/scaling/packing (see ffft.cpp's
% StatusNote for the ruled-out list). The blocker is that the mri volume's
% own spectrum is too rich to invert a packing from statistically. These
% cases use small 8x8x8 volumes whose 3-D DFTs are known in closed form,
% so the packing (real part vs imaginary vs magnitude, any scale factor,
% any fft-shift, and the real-vs-complex mode difference) reads off the
% output directly, byte-for-byte, instead of by inference:
%   const   : all-10 volume. DFT is a single DC term (10*512 = 5120) at
%             bin (1,1,1), exactly zero everywhere else. Reveals the scale
%             factor and whether zeros stay zero.
%   imp_orig: unit-ish impulse at the (1,1,1) origin. DFT is a CONSTANT
%             100+0i across every bin -- purely real. Distinguishes
%             magnitude/real-part (both 100) from imaginary (0).
%   imp_off : impulse one voxel off-origin along dim 1. DFT is
%             100*exp(-2*pi*i*(k1-1)/8), whose real and imaginary parts
%             both vary in a known pattern -- the decisive discriminator
%             for real-vs-imaginary packing and any fft-shift.
% Both FFFT modes (0=Real, 1=Complex) are captured for each volume.
%
% Run exactly like s07-s14 (own matlab -batch invocation; crash-tolerant).

cfg = refcap_config();
addpath(cfg.matitkDir);

constRecipe = '10*ones(8,8,8)';
constVol = 10 * ones(8, 8, 8);

impOrigRecipe = 'b = zeros(8,8,8); b(1,1,1) = 100;';
impOrig = zeros(8, 8, 8); impOrig(1, 1, 1) = 100;

impOffRecipe = 'b = zeros(8,8,8); b(2,1,1) = 100;';
impOff = zeros(8, 8, 8); impOff(2, 1, 1) = 100;

for mode = [0 1]
    modeName = 'real'; if mode == 1, modeName = 'complex'; end

    capture_case(cfg, 'FFFT', sprintf('const_%s_double', modeName), mode, ...
        constVol, struct('inputRecipe', constRecipe));

    capture_case(cfg, 'FFFT', sprintf('imporig_%s_double', modeName), mode, ...
        impOrig, struct('inputRecipe', impOrigRecipe));

    capture_case(cfg, 'FFFT', sprintf('impoff_%s_double', modeName), mode, ...
        impOff, struct('inputRecipe', impOffRecipe));
end

local_mark_complete(cfg, 's15');
