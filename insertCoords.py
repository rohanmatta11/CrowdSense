import os
from supabase import create_client, Client
supabase: Client = create_client("https://xtircqvtskrecopuyhkg.supabase.co", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh0aXJjcXZ0c2tyZWNvcHV5aGtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgzOTAyNzksImV4cCI6MjA3Mzk2NjI3OX0.CWSgaCPLCGywrui5u3gQWjmxA9w71r4U6vAGzA5SS08")

def inputData(people_count, latitude, longitude):
    data = {
        "people_count": people_count,
        "Latitude": latitude,
        "Longitude": longitude,
    }
    response = supabase.table("WhereTheCrowdAt").insert([data]).execute()
    return response
