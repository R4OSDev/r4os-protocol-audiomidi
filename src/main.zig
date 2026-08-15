const r4os = @import("r4os");

comptime {
    asm (r4os.r4dev.protocolEntriesAsm("midi_init", "midi_shutdown", "midi_query", "midi_dispatch"));
}

export fn midi_init(api: *const r4os.r4dev.ProtocolApi) callconv(.c) i32 {
    var ctx = r4os.r4dev.ProtocolContext.init(api);
    ctx.logInfo("MIDI.R4P init");
    _ = ctx.registerRole("audio.midi", .audio, 0);
    _ = ctx.setStatus(.active, "MIDI event protocol active");
    return 0;
}

export fn midi_shutdown() callconv(.c) i32 {
    return 0;
}

export fn midi_query(out: *r4os.abi.ProtocolStatus) callconv(.c) i32 {
    out.* = .{
        .state = @intFromEnum(r4os.abi.ProtocolState.active),
        .flags = 0,
        .last_error = 0,
        .reserved = 0,
        .note = note("MIDI event R4P ready"),
    };
    return 0;
}

export fn midi_dispatch(op: u32, in_buffer: *const r4os.abi.ProtocolBuffer, out_buffer: *r4os.abi.ProtocolBuffer) callconv(.c) i32 {
    _ = out_buffer;
    const request = requestFromBuffer(in_buffer) orelse return r4os.abi.audio_midi_result_bad_event;
    switch (op) {
        r4os.abi.audio_midi_op_classify_event => classifyEvent(request),
        r4os.abi.audio_midi_op_self_test => selfTest(request),
        else => return r4os.abi.audio_midi_result_unsupported,
    }
    return request.result;
}

fn classifyEvent(op: *r4os.abi.AudioMidiOp) void {
    if (op.channel > 15) {
        op.result = r4os.abi.audio_midi_result_bad_event;
        return;
    }
    const status = op.status & 0xF0;
    op.normalized_status = status;
    op.event = r4os.abi.audio_midi_event_ignore;
    switch (status) {
        0x80 => {
            op.event = r4os.abi.audio_midi_event_note_off;
            op.note = op.data1 & 0x7F;
            op.velocity = op.data2 & 0x7F;
        },
        0x90 => {
            op.note = op.data1 & 0x7F;
            op.velocity = op.data2 & 0x7F;
            if (op.velocity == 0) {
                op.event = r4os.abi.audio_midi_event_note_off;
                op.normalized_status = 0x80;
            } else {
                op.event = r4os.abi.audio_midi_event_note_on;
            }
        },
        0xB0 => {
            op.event = r4os.abi.audio_midi_event_control;
            op.controller = op.data1 & 0x7F;
            op.value = op.data2 & 0x7F;
        },
        0xC0 => {
            op.event = r4os.abi.audio_midi_event_program;
            op.program = op.data1 & 0x7F;
        },
        0xD0 => {
            op.event = r4os.abi.audio_midi_event_channel_pressure;
            op.value = op.data1 & 0x7F;
        },
        0xE0 => {
            op.event = r4os.abi.audio_midi_event_pitch_bend;
            op.value = op.data2 & 0x7F;
        },
        else => {},
    }
    op.result = r4os.abi.audio_midi_result_ok;
}

fn selfTest(op: *r4os.abi.AudioMidiOp) void {
    var probe: r4os.abi.AudioMidiOp = .{ .channel = 2, .status = 0x90, .data1 = 60, .data2 = 0 };
    classifyEvent(&probe);
    if (probe.result != r4os.abi.audio_midi_result_ok or probe.event != r4os.abi.audio_midi_event_note_off or probe.normalized_status != 0x80) {
        op.result = r4os.abi.audio_midi_result_bad_event;
        return;
    }
    probe = .{ .channel = 3, .status = 0xB0, .data1 = 7, .data2 = 100 };
    classifyEvent(&probe);
    if (probe.event != r4os.abi.audio_midi_event_control or probe.controller != 7 or probe.value != 100) {
        op.result = r4os.abi.audio_midi_result_bad_event;
        return;
    }
    probe = .{ .channel = 1, .status = 0xC0, .data1 = 12 };
    classifyEvent(&probe);
    if (probe.event != r4os.abi.audio_midi_event_program or probe.program != 12) {
        op.result = r4os.abi.audio_midi_result_bad_event;
        return;
    }
    op.result = r4os.abi.audio_midi_result_ok;
}

fn requestFromBuffer(buffer: *const r4os.abi.ProtocolBuffer) ?*r4os.abi.AudioMidiOp {
    if (buffer.data == null) return null;
    if (buffer.len < @sizeOf(r4os.abi.AudioMidiOp)) return null;
    return @ptrCast(@alignCast(buffer.data.?));
}

fn note(comptime text: []const u8) [64]u8 {
    var out: [64]u8 = .{0} ** 64;
    @memcpy(out[0..text.len], text);
    return out;
}
