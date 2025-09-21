import Foundation

// MARK: - Config
let supabaseURL = URL(string: "https://xtircqvtskrecopuyhkg.supabase.co")!
let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh0aXJjcXZ0c2tyZWNvcHV5aGtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgzOTAyNzksImV4cCI6MjA3Mzk2NjI3OX0.CWSgaCPLCGywrui5u3gQWjmxA9w71r4U6vAGzA5SS08"

// MARK: - Models
struct CrowdRow: Codable {
    let ID: Int
    let people_count: Int
    let Latitude: Double
    let Longitude: Double
    let created_at: String
}

// MARK: - Helpers
func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let dlat = lat2 - lat1
    let dlon = lon2 - lon1
    return sqrt(dlat * dlat + dlon * dlon)
}

func makeRequest(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
    var req = URLRequest(url: supabaseURL.appendingPathComponent("/rest/v1/\(path)"))
    req.httpMethod = method
    req.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("true", forHTTPHeaderField: "Prefer") // return inserted rows
    req.httpBody = body
    return req
}

// MARK: - Insert + cleanup logic
func inputData(peopleCount: Int, latitude: Double, longitude: Double, completion: @escaping () -> Void) {
    let insert = [
        ["people_count": peopleCount, "Latitude": latitude, "Longitude": longitude]
    ]
    
    guard let body = try? JSONSerialization.data(withJSONObject: insert) else { return }
    let req = makeRequest(path: "WhereTheCrowdAt", method: "POST", body: body)
    
    URLSession.shared.dataTask(with: req) { data, _, error in
        if let error = error {
            print("Insert error:", error)
            return
        }
        guard let data = data,
              let inserted = try? JSONDecoder().decode([CrowdRow].self, from: data),
              let last = inserted.first else {
            print("Insert decode error")
            return
        }
        
        let lastID = last.ID
        
        // Now fetch all rows except the new one
        var selectReq = makeRequest(path: "WhereTheCrowdAt?select=*")
        URLSession.shared.dataTask(with: selectReq) { rowsData, _, _ in
            guard let rowsData = rowsData,
                  let rows = try? JSONDecoder().decode([CrowdRow].self, from: rowsData) else {
                print("Select decode error")
                return
            }
            
            let now = Date()
            let formatter = ISO8601DateFormatter()
            
            for row in rows where row.ID != lastID {
                if let rowTime = formatter.date(from: row.created_at) {
                    let tooClose = distance(lat1: latitude, lon1: longitude,
                                            lat2: row.Latitude, lon2: row.Longitude) < 0.01
                    let tooOld = now.timeIntervalSince(rowTime) > 30 * 60
                    
                    if tooClose || tooOld {
                        var delReq = makeRequest(path: "WhereTheCrowdAt?id=eq.\(row.ID)", method: "DELETE")
                        URLSession.shared.dataTask(with: delReq).resume()
                    }
                }
            }
        }.resume()
    }.resume()
}

// MARK: - Cleanup old rows
func cleanupOldRows() {
    var req = makeRequest(path: "WhereTheCrowdAt?select=*")
    
    URLSession.shared.dataTask(with: req) { data, _, _ in
        guard let data = data,
              let rows = try? JSONDecoder().decode([CrowdRow].self, from: data) else { return }
        
        let now = Date()
        let formatter = ISO8601DateFormatter()
        
        for row in rows {
            if let rowTime = formatter.date(from: row.created_at),
               now.timeIntervalSince(rowTime) > 30 * 60 {
                var delReq = makeRequest(path: "WhereTheCrowdAt?id=eq.\(row.ID)", method: "DELETE")
                URLSession.shared.dataTask(with: delReq).resume()
            }
        }
    }.resume()
}


