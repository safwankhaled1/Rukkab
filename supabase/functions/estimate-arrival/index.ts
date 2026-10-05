import { createClient } from "npm:@supabase/supabase-js@2";
async function estimate(request: Request) {
  if (request.method !== "POST")
    return new Response("Method not allowed", { status: 405 });
  const url = Deno.env.get("SUPABASE_URL")!,
    anon = Deno.env.get("SUPABASE_ANON_KEY")!,
    googleKey = Deno.env.get("GOOGLE_ROUTES_API_KEY");
  const client = createClient(url, anon, {
    global: {
      headers: { Authorization: request.headers.get("Authorization") ?? "" },
    },
    auth: { persistSession: false },
  });
  const {
    data: { user },
    error: authError,
  } = await client.auth.getUser();
  if (authError || !user) return new Response("Unauthorized", { status: 401 });
  if (!googleKey) return new Response("Estimates unavailable", { status: 503 });
  try {
    const { booking_id } = await request.json();
    const { data: b, error } = await client
      .from("bookings")
      .select("*,trips(*)")
      .eq("id", booking_id)
      .single();
    if (
      error ||
      b.rider_id !== user.id ||
      !["confirmed", "boarded"].includes(b.state) ||
      b.trips.state !== "active"
    )
      return new Response("Forbidden", { status: 403 });
    const { data: cached } = await client
      .from("arrival_estimates")
      .select("*")
      .eq("booking_id", booking_id)
      .maybeSingle();
    if (
      cached &&
      cached.target_state === b.state &&
      Date.now() - Date.parse(cached.created_at) < 30000
    )
      return Response.json(cached);
    const { data: location } = await client
      .from("vehicle_locations")
      .select("latitude,longitude,updated_at")
      .eq("vehicle_id", b.trips.vehicle_id)
      .single();
    if (!location || Date.now() - Date.parse(location.updated_at) > 120000)
      return new Response("Location stale", { status: 409 });
    let destination: Record<string, unknown>;
    if (b.state === "confirmed" && b.pickup_latitude != null)
      destination = {
        location: {
          latLng: {
            latitude: b.pickup_latitude,
            longitude: b.pickup_longitude,
          },
        },
      };
    else if (b.state === "boarded" && b.destination_stop_id) {
      const { data: stop } = await client
        .from("stops")
        .select("latitude,longitude")
        .eq("id", b.destination_stop_id)
        .single();
      if (!stop)
        return new Response("Destination unavailable", { status: 409 });
      destination = { location: { latLng: stop } };
    } else
      destination = {
        address:
          b.state === "boarded"
            ? b.dropoff_text || b.trips.destination
            : b.pickup_text || b.trips.origin,
      };
    const response = await fetch(
      "https://routes.googleapis.com/directions/v2:computeRoutes",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": googleKey,
          "X-Goog-FieldMask": "routes.duration,routes.distanceMeters",
        },
        signal: AbortSignal.timeout(8000),
        body: JSON.stringify({
          origin: {
            location: {
              latLng: {
                latitude: location.latitude,
                longitude: location.longitude,
              },
            },
          },
          destination,
          travelMode: "DRIVE",
          routingPreference: "TRAFFIC_AWARE",
          languageCode: "ar",
          units: "METRIC",
        }),
      },
    );
    if (!response.ok)
      return new Response("Routing unavailable", { status: 503 });
    const result = await response.json();
    const route = result.routes?.[0];
    if (!route) return new Response("No route estimate", { status: 409 });
    const estimate = {
      booking_id,
      target_state: b.state,
      minutes: Math.ceil(parseFloat(route.duration) / 60),
      distance_m: route.distanceMeters,
      created_at: new Date().toISOString(),
    };
    const service = createClient(
      url,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    await service.from("arrival_estimates").upsert(estimate);
    return Response.json(estimate);
  } catch {
    return new Response("Estimate unavailable", { status: 503 });
  }
}
Deno.serve(async (request) => {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (request.method === "OPTIONS")
    return new Response(null, { status: 204, headers });
  const response = await estimate(request);
  for (const [key, value] of Object.entries(headers))
    response.headers.set(key, value);
  return response;
});
