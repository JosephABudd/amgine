const std = @import("std");
const rand = std.crypto.random;

pub const SerialRotor = struct {
    encodes: [256]u8,
    rotation_distance: u8,
    noisey: bool,

    pub fn deinit(self: *SerialRotor, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

fn initSerialRotor(rotor: *Rotor) !*SerialRotor {
    const serial_rotor = try rotor.allocator.create(SerialRotor);
    serial_rotor.rotation_distance = rotor.rotation_distance;
    serial_rotor.noisey = rotor.noisey;
    for (rotor.encodes, 0..) |v, i| {
        serial_rotor.encodes[i] = v;
    }
    return serial_rotor;
}

test "initSerialRotor" {
    var rotor = try init(std.testing.allocator);
    defer rotor.deinit();

    var serial_rotor: *SerialRotor = try initSerialRotor(rotor);
    defer serial_rotor.deinit(std.testing.allocator);

    try std.testing.expect(serial_rotor.rotation_distance == rotor.rotation_distance);
    try std.testing.expect(serial_rotor.noisey == rotor.noisey);
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try std.testing.expect(serial_rotor.encodes[i] == rotor.encodes[i]);
    }
}

/// Rotor represents a rotating disc of 256 unique and randomly sorted u8 values.
/// .encodes is the 256 encoded values, indexed by the values of raw bytes.
/// .decodes is the 256 byte values, indexed by the values of encoded bytes.
/// .encodes and .decodes are exact inverses of each other.
/// Rotation is simulated with .rotation_offset and .rotation_distance.
/// See functions rotate(..), encode(..) and decode(..).
/// Rotor is added with .init() and removed with rotor.deinit().
pub const Rotor = struct {
    encodes: [256]u8, // example: encodes['a'] is the Rotor's encoding of 'a' which is 0x23.
    decodes: [256]u8, // example: decodes[0x23] is 'a'.
    rotation_offset: u8,
    rotation_distance: u8,
    allocator: std.mem.Allocator,
    noisey: bool,

    /// deinit removes the Rotor from memory.
    pub fn deinit(self: *Rotor) void {
        self.allocator.destroy(self);
    }

    /// serial returns a serial version of Rotor.
    pub fn serial(self: *Rotor) !*SerialRotor {
        return initSerialRotor(self);
    }

    pub fn copy(self: *Rotor) !*Rotor {
        var rotor: *Rotor = try self.allocator.create(Rotor);
        rotor.allocator = self.allocator;
        rotor.noisey = self.noisey;
        rotor.rotation_offset = self.rotation_offset;
        rotor.rotation_distance = self.rotation_distance;
        for (self.encodes, 0..) |v, i| {
            rotor.encodes[i] = v;
            rotor.decodes[v] = @as(u8, @intCast(i));
        }
        return rotor;
    }

    /// isNoisey returns if the Rotor add/removes noise.
    pub fn isNoisey(self: *Rotor) bool {
        return self.noisey;
    }

    test "isNoisey" {
        var rotor = try init(std.testing.allocator);
        defer rotor.deinit();

        const noisey: bool = true;
        rotor.noisey = noisey;
        try std.testing.expect(rotor.isNoisey() == noisey);
    }

    /// reset sets the rotation_offset to 0.
    pub fn reset(self: *Rotor) void {
        self.rotation_offset = 0;
    }

    test "reset" {
        var rotor = try init(std.testing.allocator);
        defer rotor.deinit();

        rotor.rotation_offset = 1;
        rotor.reset();
        try std.testing.expect(rotor.rotation_offset == 0);
    }

    /// rotate simulates a rotation of the rotor.
    /// It adds the rotation distance to the rotation offset.
    pub fn rotate(self: *Rotor) void {
        self.rotation_offset +%= self.rotation_distance;
    }

    test "rotate" {
        var rotor = try init(std.testing.allocator);
        defer rotor.deinit();

        rotor.rotation_offset = 0;
        rotor.rotate();
        try std.testing.expect(rotor.rotation_offset == rotor.rotation_distance);

        rotor.rotation_offset = 255;
        var want_rotation_offset: usize = rotor.rotation_offset +% rotor.rotation_distance;
        rotor.rotate();
        try std.testing.expect(rotor.rotation_offset == want_rotation_offset);
    }

    /// decode returns the encoded byte's original value.
    pub fn decode(self: *Rotor, encoded_byte: u8) u8 {
        // Remove the rotation offset which only simulates rotation.
        var true_encoded_byte = encoded_byte -% self.rotation_offset;
        return self.decodes[true_encoded_byte];
    }

    test "decode" {
        var rotor = try init(std.testing.allocator);
        defer rotor.deinit();

        var got_decoded: u8 = 0;
        rotor.rotation_offset = 20;
        for (rotor.decodes, 0..) |want_decoded, encoded_usize| {
            var fixed_encoded_u8 = @as(u8, @intCast(encoded_usize));
            fixed_encoded_u8 +%= rotor.rotation_offset;
            got_decoded = rotor.decode(fixed_encoded_u8);
            // std.debug.print("\ngot_decoded:{d}, want_decoded:{d}", .{ got_decoded, want_decoded });
            try std.testing.expect(got_decoded == want_decoded);
        }
    }

    /// encode returns a bytes encoding.
    pub fn encode(self: *Rotor, byte: u8) u8 {
        var encoding: u8 = self.encodes[byte];
        // Add the rotation offset to simulate rotation.
        encoding +%= self.rotation_offset;
        return encoding;
    }

    test "encode" {
        var rotor = try init(std.testing.allocator);
        defer rotor.deinit();

        var got_encoded: u8 = 0;
        var want_encoded: u8 = 0;
        rotor.rotation_offset = 30;
        for (rotor.encodes, 0..) |encoding, original_usize| {
            want_encoded = encoding +% rotor.rotation_offset;
            var original_u8 = @as(u8, @intCast(original_usize));
            got_encoded = rotor.encode(original_u8);
            try std.testing.expect(got_encoded == want_encoded);
        }
    }

    /// noise returns a random byte value.
    pub fn noise(self: *Rotor) u8 {
        _ = self;
        return rand.intRangeAtMost(u8, 0, 255);
    }

    /// initEncodesDecodes makes a slice of random bytes with no repetition.
    fn initEncodesDecodes(self: *Rotor) void {
        var i: usize = 0;
        var encode_u8: u8 = 0;
        while (i < 256) : ({
            i += 1;
        }) {
            encode_u8 = @as(u8, @intCast(i));
            self.encodes[i] = encode_u8;
        }
        // Shuffle the list 5 times.
        i = 0;
        while (i < 5) : (i += 1) {
            var from: usize = 0;
            while (from < 256) : (from += 1) {
                // to is a random index.
                var to = rand.intRangeAtMost(usize, 0, 255);
                encode_u8 = self.encodes[to];
                self.encodes[to] = self.encodes[from];
                self.encodes[from] = encode_u8;
            }
        }
        i = 0;
        while (i < 256) : ({
            i += 1;
        }) {
            encode_u8 = self.encodes[i];
            var encode_usize: usize = @as(usize, encode_u8);
            var decode_u8: u8 = @as(u8, @intCast(i));
            self.decodes[encode_usize] = decode_u8;
        }
    }
};

/// init allocates the memory for a Rotor.
/// Returns a pointer to the Rotor.
/// Rotor must be removed from memory with Rotor.deinit().
pub fn init(allocator: std.mem.Allocator) !*Rotor {
    // Create this rotor.
    var rotor: *Rotor = try allocator.create(Rotor);
    rotor.allocator = allocator;
    rotor.noisey = rand.boolean();
    rotor.rotation_offset = 0;
    rotor.rotation_distance = rand.intRangeAtMost(u8, 0, 255);
    // Create random encodes and decodes.
    rotor.initEncodesDecodes();
    return rotor;
}

test "init, encode, decode" {
    var rotor: *Rotor = try init(std.testing.allocator);
    defer rotor.deinit();

    var decode_u8: u8 = 0;
    while (decode_u8 <= 255) : ({
        decode_u8 +%= 1;
        if (decode_u8 == 0) {
            break;
        }
    }) {
        // Test the fn encode which returns a bytes encoding.
        var got_encode_u8: u8 = rotor.encode(decode_u8);
        // rotor.encode adds self.starting_value_index to the encoding.
        //  so the corrections here for an index in rotor.decodes.
        var want_encode_u8: u8 = rotor.encodes[decode_u8] +% rotor.rotation_offset;
        try std.testing.expect(want_encode_u8 == got_encode_u8);
    }

    var encode_u8: u8 = 0;
    while (encode_u8 <= 255) : ({
        encode_u8 +%= 1;
        if (encode_u8 == 0) {
            break;
        }
    }) {
        // adjusted_encode_u8 is what fn rotor.encode would return.
        // rotor.encode always adds rotor.rotation_offset to the encoding.
        // likewise, rotor.decode always subtracts rotor.rotation_offset.
        var adjusted_encode_u8: u8 = encode_u8 +% rotor.rotation_offset;
        var got_decode_u8: u8 = rotor.decode(adjusted_encode_u8);
        var want_decode_u8: u8 = rotor.decodes[encode_u8];
        try std.testing.expect(want_decode_u8 == got_decode_u8);
    }
}

pub fn initFromSerial(allocator: std.mem.Allocator, serial_rotor: *SerialRotor) !*Rotor {
    // Create this rotor.
    var rotor = try allocator.create(Rotor);

    rotor.allocator = allocator;
    rotor.noisey = serial_rotor.noisey;
    rotor.rotation_distance = serial_rotor.rotation_distance;
    for (serial_rotor.encodes, 0..) |encode_u8, raw_usize| {
        rotor.encodes[raw_usize] = encode_u8;
        var raw_u8 = @as(u8, @intCast(raw_usize));
        rotor.decodes[encode_u8] = raw_u8;
    }
    return rotor;
}

test "initFromSerial" {
    var rotor_want: *Rotor = try init(std.testing.allocator);
    defer rotor_want.deinit();

    var rotor_serial: *SerialRotor = try rotor_want.serial();
    defer rotor_serial.deinit(std.testing.allocator);

    var rotor_got: *Rotor = try initFromSerial(std.testing.allocator, rotor_serial);
    defer rotor_got.deinit();

    try std.testing.expect(rotor_want.noisey == rotor_got.noisey);
    try std.testing.expect(rotor_want.rotation_distance == rotor_got.rotation_distance);
}
