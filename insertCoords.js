// insertCoords.js
const { createClient } = require("@supabase/supabase-js");
const cron = require("node-cron");

// Connect to Supabase
const supabase = createClient(
  "https://xtircqvtskrecopuyhkg.supabase.co",
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh0aXJjcXZ0c2tyZWNvcHV5aGtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgzOTAyNzksImV4cCI6MjA3Mzk2NjI3OX0.CWSgaCPLCGywrui5u3gQWjmxA9w71r4U6vAGzA5SS08"
);

function distance(lat1, lon1, lat2, lon2) {
  const dlat = lat2 - lat1;
  const dlon = lon2 - lon1;
  return Math.sqrt(dlat * dlat + dlon * dlon);
}

// Insert + cleanup logic
async function inputData(people_counts, latitude, longitude) {
  const { data, error } = await supabase
    .from("WhereTheCrowdAt")
    .insert([{ people_count: people_counts, Latitude: latitude, Longitude: longitude }])
    .select();
  const lastID = data[0].ID;
  if (error) {
    console.error("Insert error:", error);
    return;
  }
  // Fetch all rows
  const { data: rows, error: selectError } = await supabase
    .from("WhereTheCrowdAt")
    .select("*")
    .not("ID", "eq", lastID); // Exclude the newly inserted row

  if (selectError) {
    console.error("Select error:", selectError);
    return;
  }

  const now = new Date();

  for (const row of rows) {
    const rowTime = new Date(row.created_at);

    if (
      row.ID != lastID && (distance(latitude, longitude, row.Latitude, row.Longitude) < 0.01 ||
      now - rowTime > 30 * 60 * 1000)
    ) {
      await supabase.from("WhereTheCrowdAt").delete().eq("ID", row.ID);
    }
    // console.log(distance(latitude, longitude, row.Latitude, row.Longitude));
  }

  return data;
}

// Cleanup function for rows older than 30 min
async function cleanupOldRows() {
  const { data: rows, error } = await supabase
    .from("WhereTheCrowdAt")
    .select("*");

  if (error) {
    console.error("Select error:", error);
    return;
  }

  const now = new Date();

  for (const row of rows) {
    const rowTime = new Date(row.created_at);

    if (now - rowTime > 30 * 60 * 1000) {
      await supabase.from("WhereTheCrowdAt").delete().eq("ID", row.ID);
    }
  }
}

// Run cleanup every minute
cron.schedule("* * * * *", cleanupOldRows);

// Example usage (optional)
inputData(100, 5, -122.4194);
