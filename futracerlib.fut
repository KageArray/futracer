include futracerlib.base.F32
include futracerlib.base.I32
include futracerlib.transformations
include futracerlib.color

default (i32, f32)

type triangle = (F32.point3D, F32.point3D, F32.point3D)
type point_projected = (i32, i32, f32)
type triangle_projected = (point_projected, point_projected, point_projected)
type point_barycentric = (i32, I32.point3D, F32.point3D)
type camera = (F32.point3D, F32.angles)

fun normalize_point
  (((xc, yc, zc), (ax, ay, az)) : camera)
  (p0 : F32.point3D)
  : F32.point3D =
      let p1 = (translate_point (-xc, -yc, -zc) p0)
      let p2 = rotate_point (-ax, -ay, -az) (0.0, 0.0, 0.0) p1
      in p2

fun normalize_triangle
  (camera : camera)
  ((p0, p1, p2) : triangle)
  : triangle =
  let p0n = normalize_point camera p0
  let p1n = normalize_point camera p1
  let p2n = normalize_point camera p2
  let triangle' = (p0n, p1n, p2n)
  in triangle'

fun project_point
  (w : i32) (h : i32)
  ((x, y, z) : F32.point3D)
  : I32.point2D =
  let view_dist = 600.0
  let z_ratio = if z >= 0.0
                then (view_dist + z) / view_dist
                else 1.0 / ((view_dist - z) / view_dist)

  let x_projected = x / z_ratio + f32 w / 2.0
  let y_projected = y / z_ratio + f32 h / 2.0

  in (i32 x_projected, i32 y_projected)

fun project_triangle
  (w : i32) (h : i32)
  (triangle : triangle)
  : triangle_projected =
  let ((x0, y0, z0), (x1, y1, z1), (x2, y2, z2)) = triangle
  let (xp0, yp0) = project_point w h (x0, y0, z0)
  let (xp1, yp1) = project_point w h (x1, y1, z1)
  let (xp2, yp2) = project_point w h (x2, y2, z2)
  let triangle_projected = ((xp0, yp0, z0), (xp1, yp1, z1), (xp2, yp2, z2))
  in triangle_projected

fun in_range (t : i32) (a : i32) (b : i32) : bool =
  (a < b && a <= t && t <= b) || (b <= a && b <= t && t <= a)

fun barycentric_coordinates
  ((x, y) : I32.point2D)
  (triangle : triangle_projected)
  : point_barycentric =
  let ((xp0, yp0, _z0), (xp1, yp1, _z1), (xp2, yp2, _z2)) = triangle
  let factor = (yp1 - yp2) * (xp0 - xp2) + (xp2 - xp1) * (yp0 - yp2)
  let a = ((yp1 - yp2) * (x - xp2) + (xp2 - xp1) * (y - yp2))
  let b = ((yp2 - yp0) * (x - xp2) + (xp0 - xp2) * (y - yp2))
  let c = factor - a - b
  let factor' = f32 factor
  let an = f32 a / factor'
  let bn = f32 b / factor'
  let cn = 1.0 - an - bn
  in (factor, (a, b, c), (an, bn, cn))

fun is_inside_triangle
  ((factor, (a, b, c), (_an, _bn, _cn)) : point_barycentric)
  : bool =
  in_range a 0 factor && in_range b 0 factor && in_range c 0 factor

fun interpolate_z
  (triangle : triangle_projected)
  ((_factor, (_a, _b, _c), (an, bn, cn)) : point_barycentric)
  : f32 =
  let ((_xp0, _yp0, z0), (_xp1, _yp1, z1), (_xp2, _yp2, z2)) = triangle
  in an * z0 + bn * z1 + cn * z2

fun dist
  ((x0, y0, z0) : F32.point3D)
  ((x1, y1, z1) : F32.point3D)
  : f32 =
  sqrt32((x1 - x0)**2.0 + (y1 - y0)**2.0 + (z1 - z0)**2.0)

fun close_enough
  (draw_dist : f32)
  ((p_camera, _) : camera)
  (triangle : triangle)
  : bool =
  (dist p_camera (#0 triangle) <= draw_dist) ||
  (dist p_camera (#1 triangle) <= draw_dist) ||
  (dist p_camera (#2 triangle) <= draw_dist)

fun render_triangles
  (camera : camera)
  (triangles : []triangle)
  (w : i32) (h : i32)
  (draw_dist : f32)
  : [w][h]pixel =
  let triangles_close = filter (close_enough draw_dist camera) triangles
  in render_triangles' camera triangles_close w h

fun render_triangles'
  (camera : camera)
  (triangles : [tn]triangle)
  (w : i32) (h : i32)
  : [w][h]pixel =
  let bbox_coordinates =
    reshape (w * h)
    (map (fn (x : i32) : [](i32, i32) =>
            map (fn (y : i32) : (i32, i32) =>
                   (x, y))
                (iota h))
         (iota w))

  let triangles_normalized = map (normalize_triangle camera)
                                 triangles

  let triangles_projected = map (project_triangle w h)
                                triangles_normalized

  let baryss = map (fn (p : I32.point2D) : [tn]point_barycentric =>
                      map (barycentric_coordinates p)
                          triangles_projected)
                   bbox_coordinates

  let is_insidess = map (fn (barys : [tn]point_barycentric) : [tn]bool =>
                           map is_inside_triangle barys)
                       baryss

  let z_valuess = map (fn (barys : [tn]point_barycentric) : [tn]f32 =>
                         zipWith interpolate_z triangles_projected barys)
                      baryss

  let colorss = map (fn (z_values : []f32) : [tn]hsv =>
                       map (fn (z : f32) : hsv =>
                              let h = 120.0
                              let s = 0.8
                              let v = F32.min 1.0 (1.0 / (z * 0.01))
                              in (h, s, v))
                           z_values)
                    z_valuess

  let (_mask, _z_values, colors) =
    unzip (zipWith (fn (is_insides : [tn]bool)
                       (z_values : [tn]f32)
                       (colors : [tn]hsv)
                       : (bool, f32, hsv) =>
                      let neutral_element = (false, -1.0, (0.0, 0.0, 0.0)) in
                      (reduce (fn ((in_triangle0, z0, hsv0)
                                   : (bool, f32, hsv))
                                  ((in_triangle1, z1, hsv1)
                                   : (bool, f32, hsv))
                                  : (bool, f32, hsv) =>
                                 if (in_triangle0 && z0 >= 0.0 &&
                                     (z1 < 0.0 || !in_triangle1 || z0 < z1))
                                 then (true, z0, hsv0)
                                 else if (in_triangle1 && z1 >= 0.0 &&
                                          (z0 < 0.0 || !in_triangle0 || z1 < z0))
                                 then (true, z1, hsv1)
                                 else if (in_triangle0 && z0 > 0.0 &&
                                          in_triangle1 && z1 > 0.0 && z0 == z1)
                                 then (true, z0, hsv_average hsv0 hsv1)
                                 else neutral_element)
                              neutral_element
                              (zip is_insides z_values colors)))
                   is_insidess z_valuess colorss)

  let pixels = map (fn x => rgb_to_pixel (hsv_to_rgb x)) colors
  let frame = reshape (w, h) pixels
  in frame

entry render_triangles_raw
  (
   w : i32,
   h : i32,
   draw_dist : f32,
   x0s : [n]f32,
   y0s : [n]f32,
   z0s : [n]f32,
   x1s : [n]f32,
   y1s : [n]f32,
   z1s : [n]f32,
   x2s : [n]f32,
   y2s : [n]f32,
   z2s : [n]f32,
   c_x : f32,
   c_y : f32,
   c_z : f32,
   c_ax : f32,
   c_ay : f32,
   c_az : f32
  ) : [w][h]pixel =
  let camera = ((c_x, c_y, c_z), (c_ax, c_ay, c_az))
  let p0s = zip x0s y0s z0s
  let p1s = zip x1s y1s z1s
  let p2s = zip x2s y2s z2s
  let triangles = zip p0s p1s p2s
  in render_triangles camera triangles w h draw_dist
