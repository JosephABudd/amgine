const std = @import("std");
const _rotor_ = @import("rotor.zig");
const rand = std.crypto.random;
const json = std.json;

const SerialSecret = struct {
    rotors: [5]*_rotor_.SerialRotor,
    prefix_length: usize,

    fn marshal(
        self: *SerialSecret,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        try json.stringify(self, .{}, output.writer());
        return output.toOwnedSlice();
    }

    pub fn deinit(self: *SerialSecret, allocator: std.mem.Allocator) void {
        for (self.rotors) |rotor| {
            rotor.deinit(allocator);
        }
        allocator.destroy(self);
    }
};

/// Secret is the part that the amgine requires to run.
/// The same secret that is used to encode must be used to decode.
/// Secret is added with .init() and removed with secret.deinit().
pub const Secret = struct {
    // rotors
    rotor_index: usize,
    rotors: [5]*_rotor_.Rotor,
    prefix_length: usize,
    allocator: std.mem.Allocator,

    /// deinit removes the secret from memory.
    pub fn deinit(self: *Secret) void {
        for (self.rotors) |rotor| {
            rotor.deinit();
        }
        self.allocator.destroy(self);
    }

    pub fn marshal(self: *Secret) ![]u8 {
        const serial_secret = try self.serial();
        defer serial_secret.deinit(self.allocator);
        var marshalled: []u8 = try serial_secret.marshal(self.allocator);
        return marshalled;
    }

    /// serial returns a serial version of Secret.
    fn serial(self: *Secret) !*SerialSecret {
        const serial_secret: *SerialSecret = try self.allocator.create(SerialSecret);
        serial_secret.prefix_length = self.prefix_length;
        for (self.rotors, 0..) |rotor, i| {
            serial_secret.rotors[i] = try rotor.serial();
            errdefer {
                var j: usize = 0;
                while (j < i) : (j += 1) {
                    serial_secret.rotors[i].deinit();
                }
                self.allocator.destroy(serial_secret);
            }
        }
        return serial_secret;
    }

    test "serial" {
        var secret = try init(std.testing.allocator, 0);
        defer secret.deinit();

        var serial_secret: *SerialSecret = try secret.serial();
        defer serial_secret.deinit(std.testing.allocator);

        try std.testing.expect(secret.prefix_length == serial_secret.prefix_length);
        var i: usize = 0;
        while (i < secret.rotor_index) : (i += 1) {
            var rotor_src: []u8 = &secret.rotors[i].encodes;
            var rotor_dst: []u8 = &serial_secret.rotors[i].encodes;
            var j: usize = 0;
            while (j <= 255) : (j += 1) {
                try std.testing.expect(rotor_src[j] == rotor_dst[j]);
            }
        }
    }

    /// reset initializes the secret and its rotors.
    pub fn reset(self: *Secret) void {
        self.rotor_index = 0;
        for (self.rotors) |rotor| {
            rotor.reset();
        }
    }

    test "reset" {
        var secret = try init(std.testing.allocator, 0);
        defer secret.deinit();

        secret.rotor_index = 10;
        secret.reset();
        try std.testing.expect(secret.rotor_index == 0);
    }

    /// rotate increments the secret's rotor index.
    pub fn rotate(self: *Secret) void {
        self.rotor_index += 1;
        if (self.rotor_index == self.rotors.len) {
            self.rotor_index = 0;
        }
    }

    test "rotate" {
        var secret = try init(std.testing.allocator, 0);
        defer secret.deinit();

        secret.rotate();
        try std.testing.expect(secret.rotor_index == 1);

        secret.rotor_index = secret.rotors.len - 1;
        secret.rotate();
        try std.testing.expect(secret.rotor_index == 0);
    }

    /// setRotorIndex increments the secret's rotor index.
    pub fn setRotorIndex(self: *Secret, index: u8) void {
        self.rotor_index = @mod(index, self.rotors.len);
    }

    test "setRotorIndex" {
        var secret = try init(std.testing.allocator, 0);
        defer secret.deinit();

        var i: usize = 0;
        var i_u8: u8 = 0;
        while (i < secret.rotors.len) : (i += 1) {
            i_u8 = @as(u8, @intCast(i));
            secret.setRotorIndex(i_u8);
            try std.testing.expect(secret.rotor_index == i);
        }

        i = 0;
        while (i < 10) : (i += 1) {
            var index: usize = secret.rotors.len + i;
            i_u8 = @as(u8, @intCast(index));
            secret.setRotorIndex(i_u8);
            var want_rotor_index: usize = @mod(index, secret.rotors.len);
            // std.debug.print("\nsecret.rotor_index:{d}, i:{d}, want_rotor_index:{d}", .{ secret.rotor_index, i, want_rotor_index });
            try std.testing.expect(secret.rotor_index == want_rotor_index);
        }
    }

    pub fn randomRotorIndex(self: *Secret) u8 {
        _ = self;
        return rand.intRangeAtMost(u8, 0, 255);
    }

    /// currentRotor returns the current rotor.
    pub fn currentRotor(self: *Secret) *_rotor_.Rotor {
        return self.rotors[self.rotor_index];
    }

    // prefixLength returns the length of the noise prefix.
    pub fn prefixLength(self: *Secret) usize {
        return self.prefix_length;
    }
};

/// init allocates the memory for a Secret.
/// Returns a pointer to the Secret or the error.
/// Secret must be removed from memory with Secret.deinit().
/// Param prefix_length is the number of initial noise bytes.
pub fn init(allocator: std.mem.Allocator, prefix_length: usize) !*Secret {
    // Build the secret.
    const secret = try allocator.create(Secret);
    secret.allocator = allocator;
    secret.prefix_length = prefix_length;
    secret.rotor_index = 0;
    var i: usize = 0;
    while (i < secret.rotors.len) : (i += 1) {
        const rotor = try _rotor_.init(allocator);
        errdefer {
            var j: usize = 0;
            while (j < i) : (j += 1) {
                secret.rotors[j].deinit();
            }
        }
        secret.rotors[i] = rotor;
    }
    return secret;
}

test "init, valueAt, indexAt" {
    const prefix_length: usize = 100;
    var secret = try init(std.testing.allocator, prefix_length);
    try std.testing.expect(prefix_length == secret.prefix_length);
    secret.deinit();
}

fn initFromSerial(allocator: std.mem.Allocator, serial_secret: *SerialSecret) !*Secret {
    // Create this rotor.
    var secret = try allocator.create(Secret);

    secret.allocator = allocator;
    secret.rotor_index = 0;
    secret.prefix_length = serial_secret.prefix_length;

    for (serial_secret.rotors, 0..) |rotor, i| {
        secret.rotors[i] = try _rotor_.initFromSerial(allocator, rotor);
        errdefer {
            var j: usize = 0;
            while (j < i) : (j += 1) {
                secret.rotors[j].deinit();
            }
            allocator.destroy(secret);
        }
    }
    return secret;
}

pub fn unmarshal(allocator: std.mem.Allocator, marshalled: []u8) !*Secret {
    var parse_from_slice: json.Parsed(SerialSecret) = try std.json.parseFromSlice(SerialSecret, allocator, marshalled, .{});
    defer parse_from_slice.deinit();
    var serial_secret: SerialSecret = parse_from_slice.value;
    return initFromSerial(allocator, &serial_secret);
}
