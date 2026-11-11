"""Compile the curves used by the original particle emitters."""
from bisect import bisect_left, bisect_right
from fractions import Fraction
import math
import struct


def float32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def scalar(bits):
    return struct.unpack('<f', struct.pack('<I', bits))[0]


def handle(key, side):
    if key['flags'][0]:
        return [0.0, 0.0]
    return [float32(value * key['weight']) for value in key[side]]


def clip_cubic(points, duration, base, bounds):
    """Keep the native cubic samples within the key's time and value ranges."""
    clipped = [points[0]]
    for left, right in zip(points, points[1:]):
        x0, y0 = left
        x1, y1 = right
        for edge in (0.0, duration):
            if min(x0, x1) < edge < max(x0, x1):
                clipped.append([edge, float32(y0 + (y1 - y0) * (edge - x0) / (x1 - x0))])
        if 0.0 <= x1 <= duration:
            clipped.append(right)
    minimum, maximum = bounds
    return [[x, float32(min(maximum - base, max(minimum - base, y)))] for x, y in clipped]


def compile_keys(keys, cubic_step, bounds=None):
    """Build the source compiler's per-key table of relative time and value."""
    compiled = [[key['time'], scalar(key['value_bits']), []] for key in keys]
    if not all(math.isfinite(point[1]) for point in compiled):
        raise ValueError("Non-finite scalar particle value")
    for index, (left, right) in enumerate(zip(keys, keys[1:])):
        start, value, _ = compiled[index]
        end, next_value, _ = compiled[index + 1]
        delta = [end - start, next_value - value]
        if delta[0] < 0.0:
            raise ValueError("Expected ordered particle keys")
        # Consecutive keys at one time are an authored jump. The evaluator
        # selects the last of them at that time, without a zero-length segment.
        if delta[0] == 0.0:
            continue
        if left['flags'][0] and right['flags'][0]:
            compiled[index][2] = [[0.0, 0.0], [float32(d) for d in delta]]
            continue
        outgoing = handle(left, 'right')
        incoming = handle(right, 'left')
        points = []
        # Native 0x102c1650 samples 30 points, including both endpoints.
        for sample in range(30):
            t = sample * cubic_step
            inv = 1.0 - t
            points.append([float32(3.0 * inv * inv * t * first
                                  + 3.0 * inv * t * t * (d + last) + t * t * t * d)
                           for d, first, last in zip(delta, outgoing, incoming)])
        if bounds is not None:
            points = clip_cubic(points, delta[0], value, bounds)
        if any(a[0] > b[0] for a, b in zip(points, points[1:])):
            raise ValueError("Particle curve requires unsupported time clipping")
        compiled[index][2] = points
    return compiled


def sample_curve(keys, conversion, time):
    """Evaluate the compiled scalar data using the original linear intervals."""
    time = float32(time)
    key_index = max(0, bisect_right([key[0] for key in keys], time) - 1)
    key_time, base, points = keys[key_index]
    value = base
    if points and time > key_time:
        times = [float32(key_time + point[0]) for point in points]
        index = max(0, min(len(points) - 2, bisect_right(times, time) - 1))
        start = float32(base + points[index][1])
        end = float32(base + points[index + 1][1])
        span = float32(times[index + 1] - times[index])
        if span > 0:
            slope = float32((end - start) / span)
            value = float32(start + float32(float32(time - times[index]) * slope))
        else:
            value = end
    return convert_value(value, conversion)


def convert_value(value, conversion):
    subtract, multiplier, add = conversion
    return float32((value - subtract) * multiplier + add)


def constant_curve(keys):
    value = keys[0][1]
    return all(key[1] == value and all(point[1] == 0.0 for point in key[2]) for key in keys)


def cache_curve(keys, conversion, resolution, neutral, constant):
    """Build the constant or sampled table read by the native emitter."""
    if constant is not None:
        value = convert_value(constant, conversion)
        return {'active': not neutral[0] <= value < neutral[1], 'count': 1, 'values': [value]}
    # The source appends a duplicate terminal value for interpolation at the
    # boundary. Both the step and each product are stored as float32.
    step = float32(100.0 / (resolution - 1))
    values = [sample_curve(keys, conversion, float32(index * step)) for index in range(resolution)]
    values.append(values[-1])
    count = len(values)
    if all(value == values[0] for value in values):
        values = values[:1]
    return {'active': True, 'count': count, 'values': values}


def extended(value):
    """Round to the source HSV converter's x87 significand precision."""
    if not value:
        return Fraction(0)
    scale = value.denominator.bit_length() - abs(value.numerator).bit_length() + 64
    units = Fraction(2) ** scale
    if abs(value) * units >= 2 ** 64:
        units /= 2
    return round(value * units) / units


def color_key(bits):
    """Decode the packed hue, value and saturation to source RGB bytes."""
    hue = ((bits >> 16) & 0x1ff) % 360
    value = (bits >> 8) & 0xff
    saturation = bits & 0xff
    angle = extended(Fraction(hue, 60))
    sector = int(angle)
    fraction = angle - sector
    low = (255 - saturation) * value // 255

    def channel(position):
        remaining = extended(255 - extended(saturation * position))
        return int(extended(extended(value * remaining) / 255))

    falling, rising = channel(fraction), channel(extended(1 - fraction))
    return [(value, rising, low), (falling, value, low), (low, value, rising),
            (low, falling, value), (rising, low, value), (value, low, falling)][sector]


def color_cache(keys, resolution):
    """Build the 0x102c2dc0 cache in the original packed ARGB order."""
    times = [key['time'] for key in keys]
    if len(times) < 2 or times[0] != 0 or times[-1] != 100 or any(a >= b for a, b in zip(times, times[1:])):
        raise ValueError("Unsupported Beautify color key times")
    colors = [color_key(key['value_bits']) for key in keys]
    slopes = [[float32((b - a) / (end - start)) for a, b in zip(left, right)]
              for start, end, left, right in zip(times, times[1:], colors, colors[1:])]
    step = float32(100.0 / (resolution - 1))
    values = []
    for index in range(resolution):
        age = float32(index * step)
        segment = bisect_left(times, age, lo=1) - 1
        red, green, blue = colors[-1]
        if segment < len(slopes):
            elapsed = age - times[segment]
            red, green, blue = (min(max(a, b), max(min(a, b), int(a + elapsed * slope)))
                                for a, b, slope in zip(colors[segment], colors[segment + 1], slopes[segment]))
        values.append(0xff000000 | (red << 16) | (green << 8) | blue)
    return values + values[-1:]


def sample_color(cache, time, time_scale, percent):
    """Read the native particle color without a per-instance color blend."""
    scaled = float32(float32(time) * time_scale)
    phase = float32(scaled - 100 * int(scaled * percent))
    return cache[int((len(cache) - 1) * phase * percent)]


def sample_draw_color(emitter, constants, remaining, lifetime, opacity, effect_opacity, parent_opacity, offset):
    """Compose the authored age curves and effect opacity into a native ARGB draw value."""
    percent = constants['percent']
    age = float32(100 - float32(remaining * 100 / lifetime))
    phase = age
    if offset is not None:
        phase = float32(age + float32(offset))
        while phase > 100:
            phase = float32(phase - 100)
    rgb = sample_color(emitter['color_cache'], phase, emitter['color_time_scale'], percent)
    index = int(emitter['curve_cache_resolution'] * age * percent)
    curve = emitter['scalar_curves']['0xdd4']['cache']['primary']['values']
    multiplier = curve[0] if len(curve) == 1 else curve[index]
    particle_alpha = float32((100 if opacity is None else float32(opacity)) * multiplier)
    effect_alpha = float32(effect_opacity)
    if parent_opacity is not None:
        effect_alpha = float32(effect_alpha * float32(parent_opacity))
    final = float32(particle_alpha * effect_alpha)
    alpha = min(255, int(final * constants['opacity_byte_scale']) & 0xffffffff)
    return (rgb & 0xffffff) | (alpha << 24)
