import { createServerFn } from "@tanstack/react-start";
import { queryOptions } from "@tanstack/react-query";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { entranceScanSchema, entranceSettingsSchema, homeSchema } from "./attendance";

export const getAttendanceHome = createServerFn({ method: "GET" }).middleware([requireSupabaseAuth]).inputValidator((v: unknown) => z.object({ gymId: z.string().uuid() }).parse(v)).handler(async ({ data, context }) => {
  const result = await context.supabase.rpc("attendance_home", { _gym: data.gymId });
  if (result.error) throw new Error("Attendance could not load. Check your gym access.");
  return homeSchema.parse(result.data);
});
export const attendanceOptions = (gymId: string) => queryOptions({ queryKey: ["attendance-home", gymId], queryFn: () => getAttendanceHome({ data: { gymId } }), refetchInterval: 30000 });
export const configureEntrance = createServerFn({ method: "POST" }).middleware([requireSupabaseAuth]).inputValidator((v: unknown) => entranceSettingsSchema.parse(v)).handler(async ({ data, context }) => {
  const result = await context.supabase.rpc("configure_attendance_point", { _gym: data.gymId, _mode: data.mode, _lat: data.latitude, _lng: data.longitude, _radius: data.radius, _verified: data.verified });
  if (result.error) throw new Error("Entrance settings could not save. Owner or manager access is required.");
  return { ok: true };
});
export const scanEntrance = createServerFn({ method: "POST" }).middleware([requireSupabaseAuth]).inputValidator((v: unknown) => entranceScanSchema.parse(v)).handler(async ({ data, context }) => {
  const result = await context.supabase.rpc("request_entrance_checkin", { _gym: data.gymId, _payload: data.payload, _device: data.device, _lat: data.latitude, _lng: data.longitude, _accuracy: data.accuracy, _location_status: data.locationStatus });
  if (result.error) throw new Error("Check-in not accepted. A linked gym membership is required.");
  return z.object({ status: z.string(), message: z.string(), checkedInAt: z.string().nullable().optional() }).parse(result.data);
});
export const resolveException = createServerFn({ method: "POST" }).middleware([requireSupabaseAuth]).inputValidator((v: unknown) => z.object({ gymId: z.string().uuid(), attempt: z.string().uuid(), approve: z.boolean(), reason: z.string().trim().min(5).max(500) }).parse(v)).handler(async ({ data, context }) => {
  const result = await context.supabase.rpc("resolve_attendance_exception", { _gym: data.gymId, _attempt: data.attempt, _approve: data.approve, _reason: data.reason });
  if (result.error) throw new Error("Confirmation failed. Check access, membership eligibility or whether this request expired or was already resolved.");
  return { ok: true };
});