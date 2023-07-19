const std = @import("std");
const _secret_ = @import("parts/secret.zig");

/// Decoder decodes an []u8 of encodes to []u8 decodes.
/// It undoes what Encoder did by using the same secret.
pub const Decoder = struct {
    secret: *_secret_.Secret,
    allocator: std.mem.Allocator,

    /// deinit removes the Decoder from memory.
    pub fn deinit(self: *Decoder) void {
        self.secret.deinit();
        self.allocator.destroy(self);
    }

    /// decode decode an []u8 returned by Encoder.encode().
    /// Param allocator is the alloctator used to create temp data and the returned []u8;
    /// Param input is the []u8 returned by Encoder.encode().
    /// Returns the decoded bytes or the error.
    pub fn decode(self: *Decoder, input: []u8) ![]u8 {
        // 1. Reset the secret.
        self.secret.reset();

        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();

        // 2. Skip over the noise prefix and read the secret's rotor index.
        var prefix_length: usize = self.secret.prefixLength();
        var rotor_index = input[prefix_length];

        // 3. Set the secret's rotor index.
        self.secret.setRotorIndex(rotor_index);

        // 4. The byte after the rotor index is the first byte of the actual encoding.
        // Ignore each noise byte.
        // Decode each encoded byte.
        var output_i: usize = 0;
        var input_i: usize = prefix_length + 1;
        while (input_i < input.len) : ({
            input_i += 1;
            output_i += 1;
        }) {
            // Get this secret's current rotor.
            var rotor = self.secret.currentRotor();

            // If this rotor is noisey then ignore this noise byte.
            if (rotor.isNoisey()) {
                // Skip over this noise.
                input_i += 1;
                output_i += 1;
                if (input_i == input.len) {
                    return error.EndedWithNoiseByte;
                }
            }

            // Read the encoded byte and decode it back to it's original value.
            var encoded = input[input_i];
            var decoded = rotor.decode(encoded);
            try output.append(decoded);

            // 1. Rotate the bytes inside the current rotor.
            rotor.rotate();
            // 2. Rotate the rotors inside this secret.
            self.secret.rotate();
        }

        // Return a single array of bytes.
        return output.toOwnedSlice();
    }
};

/// init constructs a new Decoder.
pub fn init(allocator: std.mem.Allocator, secret: *_secret_.Secret) !*Decoder {
    const decoder = try allocator.create(Decoder);
    decoder.secret = secret;
    decoder.allocator = allocator;
    return decoder;
}

test "init" {
    var allocator = std.testing.allocator;
    var secret = try _secret_.init(allocator, 3);
    defer secret.deinit();

    var decoder = try init(allocator, secret);
    defer decoder.deinit();

    try std.testing.expect(decoder.secret.prefixLength() == 3);
}
