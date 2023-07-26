const std = @import("std");
const _secret_ = @import("parts/secret.zig");

/// Encoder encodes a byte into another byte.
/// It does this according to a secret.
pub const Encoder = struct {
    secret: *_secret_.Secret,
    allocator: std.mem.Allocator,

    /// deinit removes the Encoder from memory.
    pub fn deinit(self: *Encoder) void {
        self.secret.deinit();
        self.allocator.destroy(self);
    }

    /// encode encodes the param input into indeces and noise.
    /// Param allocator is used to create the return value []u8.
    /// Returns the encoded bytes or the error.
    pub fn encode(self: *Encoder, input: []u8) ![]u8 {
        // 1. Reset the secret.
        self.secret.reset();

        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();

        // 2. Create the noise prefix.
        var rotor = self.secret.currentRotor();
        const prefix_length: usize = self.secret.prefixLength();
        var prefix_i: usize = 0;
        while (prefix_i < prefix_length) : (prefix_i += 1) {
            var noise: u8 = rotor.noise();
            try output.append(noise);
        }

        // 3. Randomly select which rotor the secret must start with.
        self.secret.reset();
        var rotor_index: u8 = self.secret.randomRotorIndex();
        self.secret.setRotorIndex(rotor_index);
        try output.append(rotor_index);

        // 4. Body.
        // Convert each original byte into
        // * an encoding of the byte value,
        // * or a noise byte value, followed by an encoding of the byte value.
        var input_i: usize = 0;
        var output_i: usize = 0;
        while (input_i < input.len) : (input_i += 1) {
            // Get this secret's current rotor.
            rotor = self.secret.currentRotor();

            // If this rotor is noisey then add a random noise value.
            if (rotor.isNoisey()) {
                output_i += 1;
                // Add noise (a random byte value) here before the actual encoded byte.
                var noise: u8 = rotor.noise();
                try output.append(noise);
            }

            output_i += 1;
            // Get the value from input and encode it.
            var value = input[input_i];
            var encoded = rotor.encode(value);
            try output.append(encoded);

            // Rotate everything.
            // 1. Rotate the bytes inside the current rotor.
            rotor.rotate();
            // 2. Rotate the rotors inside this secret.
            self.secret.rotate();
        }

        // Return a single array of bytes.
        return output.toOwnedSlice();
    }

    /// encode_deep encodes the param input into indeces and noise.
    /// Param allocator is used to create the return value []u8.
    /// Returns the encoded bytes or the error.
    pub fn encode_deep(self: *Encoder, input: []const u8) ![]u8 {
        // 1. Reset the secret.
        self.secret.reset();

        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();

        // 2. Create the noise prefix.
        {
            var rotor = self.secret.currentRotor();
            const prefix_length: usize = self.secret.prefixLength();
            var prefix_i: usize = 0;
            while (prefix_i < prefix_length) : (prefix_i += 1) {
                var noise: u8 = rotor.noise();
                try output.append(noise);
            }
        }

        // 3. Randomly select which rotor the secret must start with.
        // Use a random number between 0 & 255.
        self.secret.reset();
        var rotor_index: u8 = self.secret.randomRotorIndex();
        self.secret.setRotorIndex(rotor_index);
        try output.append(rotor_index);

        // 4. Body.
        // Convert each original byte into
        // * an encoding of the byte value,
        // * or a noise byte value, followed by an encoding of the byte value.
        var input_i: usize = 0;
        var output_i: usize = 0;
        while (input_i < input.len) : (input_i += 1) {
            // Get the value from input and encode it.
            var value = input[input_i];
            // Get this secret's rotors sorted with the current rotor first.
            // Encode each input through every rotor.
            const rotors = try self.secret.currentRotors(self.allocator);
            for (rotors, 0..) |rotor, rotor_i| {
                if (rotor_i == 0 and rotor.isNoisey()) {
                    // Add noise (a random index) here before the actual index.
                    var noise: u8 = rotor.noise();
                    try output.append(noise);
                    output_i += 1;
                }
                // Encode value with this rotor.
                value = rotor.encode(value);
            }
            try output.append(value);
            output_i += 1;

            // Rotate everything.
            // 1. Rotate the bytes inside the current rotor.
            rotors[0].rotate();
            // 2. Rotate the rotors inside this secret.
            self.secret.rotate();
        }

        // Return a single array of bytes.
        return output.toOwnedSlice();
    }
};

/// init constructs a new Encoder.
/// It makes and uses a copy of secret leaving control of secret with the caller.
pub fn init(allocator: std.mem.Allocator, secret: *_secret_.Secret) !*Encoder {
    const encoder = try allocator.create(Encoder);
    encoder.secret = try secret.copy();
    errdefer allocator.destroy(encoder);
    encoder.allocator = allocator;
    return encoder;
}

test "init" {
    var allocator = std.testing.allocator;
    var secret = try _secret_.init(allocator, 3);
    defer secret.deinit();

    var encoder = try init(allocator, secret);
    defer encoder.deinit();

    try std.testing.expect(encoder.secret.prefixLength() == 3);
}
