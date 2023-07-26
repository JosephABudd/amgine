pub const std = @import("std");
pub const amgine = @import("src/amgine.zig");
pub const secret = @import("src/engine/parts/secret.zig");

test "api" {
    const allocator = std.testing.allocator;
    // Make the secret part.
    const want_secret_part = try secret.init(std.testing.allocator, 20);
    // Make an enigma machine.
    const enigma = try amgine.init(std.testing.allocator, want_secret_part);
    errdefer want_secret_part.deinit();
    defer enigma.deinit();

    // Create a control text.
    const text = "hello world!";
    var original_data: []u8 = try allocator.alloc(u8, text.len);
    defer allocator.free(original_data);
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        original_data[i] = text[i];
    }

    // Encode the text.
    var encoded = try enigma.encode(original_data);
    defer allocator.free(encoded);

    // Decode the encoded text.
    var decoded = try enigma.decode(encoded);
    defer allocator.free(decoded);
    try std.testing.expect(original_data == decoded);

    // Check marshalling.
    var marshalled: []u8 = try want_secret_part.marshal();
    defer allocator.free(marshalled);
    var got_secret_part: *secret.Secret = try secret.unmarshal(allocator, marshalled);
    defer got_secret_part.deinit();

    try std.testing.expect(want_secret_part.prefix_length == got_secret_part.prefix_length);
    i = 0;
    while (i < want_secret_part.rotor_index) : (i += 1) {
        var rotor_src: []u8 = &want_secret_part.rotors[i].encodes;
        var rotor_dst: []u8 = &got_secret_part.rotors[i].encodes;
        var j: usize = 0;
        while (j <= 255) : (j += 1) {
            try std.testing.expect(rotor_src[j] == rotor_dst[j]);
        }
    }
}
