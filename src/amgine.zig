const std = @import("std");
const json = std.json;

const _secret_ = @import("engine/parts/secret.zig");
const _encoder_ = @import("engine/encoder.zig");
const _decoder_ = @import("engine/decoder.zig");

/// Amgine is a cypher tool.
/// It substitutes one u8 for another when encrypting and does the reverse substitution when decrypting.
/// The encoder and decoder must have the same secret.
pub const Amgine = struct {
    allocator: std.mem.Allocator,
    encoder: *_encoder_.Encoder,
    decoder: *_decoder_.Decoder,

    pub fn encode(self: *Amgine, raw: []u8) ![]u8 {
        return self.encoder.encode(raw);
    }

    pub fn decode(self: *Amgine, encoded: []u8) ![]u8 {
        return self.decoder.decode(encoded);
    }

    pub fn deinit(self: *Amgine) void {
        self.encoder.deinit();
        self.decoder.deinit();
        self.allocator.destroy(self);
    }
};

pub fn init(allocator: std.mem.Allocator, secret: *_secret_.Secret) !*Amgine {
    // Create the encoder.
    const encoder = try _encoder_.init(allocator, secret);
    // Create the decoder. It needs a copy of the secret not the secret.
    const copy_secret: *_secret_.Secret = try secret.copy();
    const decoder = try _decoder_.init(allocator, copy_secret);
    errdefer encoder.deinit();
    // Create the wheel.
    const amgine = try allocator.create(Amgine);
    errdefer {
        encoder.deinit();
        decoder.deinit();
    }
    amgine.allocator = allocator;
    amgine.encoder = encoder;
    amgine.decoder = decoder;
    return amgine;
}
