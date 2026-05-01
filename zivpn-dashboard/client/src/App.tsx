import React, { useEffect, useState } from "react";
import axios from "axios";
import { 
  Users, Activity, Server, Clock, 
  Plus, Trash2, CalendarClock, RefreshCw, AlertCircle, Search, Terminal, Globe, Shield, X, Eye, EyeOff
} from "lucide-react";

// API Config
const API_URL = "/api";

type Metrics = {
  cpu: string;
  ram: string;
  uptime: string;
  ipv4?: string;
  ipv6?: string;
};

type StatusResponse = {
  status: "active" | "stopped";
  metrics: Metrics;
};

type User = {
  username: string;
  password?: string;
  status: "active" | "expired" | "disabled";
  trial: boolean;
  created_at: string;
  expired_at: string;
};

function App() {
  const [status, setStatus] = useState<StatusResponse | null>(null);
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  
  // Search state
  const [searchQuery, setSearchQuery] = useState("");

  // Logs state
  const [showLogs, setShowLogs] = useState(false);
  const [logs, setLogs] = useState("");

  // Add User Modal State
  const [showAddModal, setShowAddModal] = useState(false);
  const [newUsername, setNewUsername] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newDays, setNewDays] = useState("30");

  // Password visibility state
  const [visiblePasswords, setVisiblePasswords] = useState<Record<string, boolean>>({});

  const togglePasswordVisibility = (username: string) => {
    setVisiblePasswords(prev => ({
      ...prev,
      [username]: !prev[username]
    }));
  };

  const fetchData = async () => {
    try {
      const [statusRes, usersRes] = await Promise.all([
        axios.get(`${API_URL}/status`),
        axios.get(`${API_URL}/users`)
      ]);
      setStatus(statusRes.data);
      setUsers(usersRes.data);
      setError("");
    } catch (err: any) {
      setError(err.message || "Failed to fetch data. Is the backend running?");
    } finally {
      setLoading(false);
    }
  };

  const fetchLogs = async () => {
    try {
      const res = await axios.get(`${API_URL}/logs`);
      setLogs(res.data.logs);
      setShowLogs(true);
    } catch (err: any) {
      alert("Failed to fetch logs: " + (err.response?.data?.error || err.message));
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 10000); // Poll every 10s
    return () => clearInterval(interval);
  }, []);

  const handleRestart = async () => {
    if (!window.confirm("Restart Zivpn service?")) return;
    try {
      await axios.post(`${API_URL}/service/restart`);
      alert("Service restarted successfully");
      fetchData();
    } catch (err: any) {
      alert("Error: " + err.message);
    }
  };

  const handleAddUser = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newUsername) return;

    try {
      await axios.post(`${API_URL}/users`, { 
        username: newUsername, 
        password: newPassword,
        days: parseInt(newDays) || 30 
      });
      setShowAddModal(false);
      setNewUsername("");
      setNewPassword("");
      setNewDays("30");
      fetchData();
    } catch (err: any) {
      alert("Error adding user: " + (err.response?.data?.error || err.message));
    }
  };

  const handleDeleteUser = async (username: string) => {
    if (!window.confirm(`Are you sure you want to delete user '${username}'?`)) return;
    try {
      await axios.delete(`${API_URL}/users/${username}`);
      fetchData();
    } catch (err: any) {
      alert("Error deleting user: " + (err.response?.data?.error || err.message));
    }
  };

  const handleExtendUser = async (username: string) => {
    const days = prompt(`Extend user '${username}' by how many days?`, "30");
    if (!days) return;

    try {
      await axios.put(`${API_URL}/users/${username}/extend`, { days: parseInt(days) });
      fetchData();
    } catch (err: any) {
      alert("Error extending user: " + (err.response?.data?.error || err.message));
    }
  };

  const calculateDaysRemaining = (expiredAt: string) => {
    const diff = new Date(expiredAt).getTime() - Date.now();
    const days = Math.ceil(diff / (1000 * 60 * 60 * 24));
    return days;
  };

  const filteredUsers = users.filter(u => 
    u.username.toLowerCase().includes(searchQuery.toLowerCase())
  );

  if (loading && !status && !error) {
    return <div className="flex h-screen items-center justify-center text-white">Loading Dashboard...</div>;
  }

  return (
    <div className="min-h-screen bg-slate-950 text-slate-200 font-sans p-6 relative">
      <div className="max-w-6xl mx-auto space-y-6">
        
        {/* Header */}
        <header className="flex flex-col md:flex-row md:justify-between items-start md:items-center gap-4 bg-slate-900 border border-slate-800 p-6 rounded-xl shadow-lg">
          <div>
            <h1 className="text-2xl font-bold text-white flex items-center gap-2">
              <Shield className="text-blue-500" />
              Zivpn Dashboard
            </h1>
            <p className="text-slate-400 text-sm mt-1">Manage and monitor your Zivpn server</p>
          </div>
          <div className="flex flex-wrap gap-3">
            <button onClick={fetchLogs} className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg flex items-center gap-2 transition-colors border border-slate-700">
              <Terminal size={18} />
              Service Logs
            </button>
            <button onClick={fetchData} className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg flex items-center gap-2 transition-colors border border-slate-700">
              <RefreshCw size={18} />
              Refresh
            </button>
            <button onClick={handleRestart} className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg flex items-center gap-2 transition-colors">
              <Activity size={18} />
              Restart Service
            </button>
          </div>
        </header>

        {error && (
          <div className="bg-red-950/50 border border-red-900 text-red-400 p-4 rounded-xl flex items-center gap-3">
            <AlertCircle size={20} />
            {error}
          </div>
        )}

        {/* Metrics Grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
          <MetricCard 
            title="Service Status" 
            value={status?.status === "active" ? "Active" : "Stopped"} 
            icon={<Activity className={status?.status === "active" ? "text-green-500" : "text-red-500"} />}
          />
          <MetricCard title="CPU Usage" value={status?.metrics?.cpu || "N/A"} icon={<Server className="text-slate-400" />} />
          <MetricCard title="RAM Usage" value={status?.metrics?.ram || "N/A"} icon={<Server className="text-slate-400" />} />
          <MetricCard title="IPv4" value={status?.metrics?.ipv4 || "Unknown"} icon={<Globe className="text-blue-400" />} />
          <MetricCard title="Uptime" value={status?.metrics?.uptime || "N/A"} icon={<Clock className="text-slate-400" />} />
        </div>

        {/* Users Section */}
        <div className="bg-slate-900 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
          <div className="p-6 border-b border-slate-800 flex flex-col md:flex-row md:justify-between items-start md:items-center gap-4">
            <h2 className="text-xl font-semibold text-white flex items-center gap-2">
              <Users className="text-purple-500" />
              User Accounts ({users.length})
            </h2>
            <div className="flex w-full md:w-auto gap-3">
              <div className="relative w-full md:w-64">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" size={18} />
                <input 
                  type="text" 
                  placeholder="Search user..." 
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-700 text-white rounded-lg pl-10 pr-4 py-2 focus:outline-none focus:border-blue-500 transition-colors"
                />
              </div>
              <button onClick={() => setShowAddModal(true)} className="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-lg flex items-center gap-2 transition-colors text-sm font-medium whitespace-nowrap">
                <Plus size={16} />
                Add User
              </button>
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left">
              <thead className="bg-slate-950 text-slate-400 text-sm uppercase">
                <tr>
                  <th className="px-6 py-4 font-medium">Username</th>
                  <th className="px-6 py-4 font-medium">Password</th>
                  <th className="px-6 py-4 font-medium">Status</th>
                  <th className="px-6 py-4 font-medium">Expired At</th>
                  <th className="px-6 py-4 font-medium">Remaining</th>
                  <th className="px-6 py-4 font-medium text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/50">
                {filteredUsers.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="px-6 py-8 text-center text-slate-500">
                      {users.length === 0 ? "No accounts found. Create one to get started." : "No accounts match your search."}
                    </td>
                  </tr>
                ) : (
                  filteredUsers.map((user) => {
                    const remaining = calculateDaysRemaining(user.expired_at);
                    const isExpired = remaining <= 0;
                    return (
                      <tr key={user.username} className="hover:bg-slate-800/50 transition-colors">
                        <td className="px-6 py-4 font-medium text-white">{user.username}</td>
                        <td className="px-6 py-4 font-mono text-sm text-slate-400 flex items-center gap-2">
                          <span>{visiblePasswords[user.username] ? user.password : "••••••••"}</span>
                          <button 
                            onClick={() => togglePasswordVisibility(user.username)}
                            className="text-slate-500 hover:text-slate-300 transition-colors"
                            title={visiblePasswords[user.username] ? "Hide password" : "Show password"}
                          >
                            {visiblePasswords[user.username] ? <EyeOff size={14} /> : <Eye size={14} />}
                          </button>
                        </td>
                        <td className="px-6 py-4">
                          <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                            isExpired ? "bg-red-900/30 text-red-400" :
                            user.status === "active" ? "bg-green-900/30 text-green-400" :
                            "bg-slate-800 text-slate-400"
                          }`}>
                            {isExpired ? "expired" : user.status}
                          </span>
                        </td>
                        <td className="px-6 py-4 text-sm text-slate-300">
                          {new Date(user.expired_at).toLocaleDateString(undefined, { 
                            year: 'numeric', month: 'short', day: 'numeric' 
                          })}
                        </td>
                        <td className="px-6 py-4">
                          <span className={`text-sm ${isExpired ? "text-red-400" : remaining <= 3 ? "text-yellow-400" : "text-green-400"}`}>
                            {isExpired ? "Expired" : `${remaining} days`}
                          </span>
                        </td>
                        <td className="px-6 py-4 text-right flex justify-end gap-2">
                          <button 
                            onClick={() => handleExtendUser(user.username)}
                            className="p-2 text-slate-400 hover:text-blue-400 hover:bg-blue-900/30 rounded-lg transition-colors"
                            title="Extend user"
                          >
                            <CalendarClock size={18} />
                          </button>
                          <button 
                            onClick={() => handleDeleteUser(user.username)}
                            className="p-2 text-slate-400 hover:text-red-400 hover:bg-red-900/30 rounded-lg transition-colors"
                            title="Delete user"
                          >
                            <Trash2 size={18} />
                          </button>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>

      </div>

      {/* Add User Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="bg-slate-900 border border-slate-800 rounded-xl shadow-2xl w-full max-w-md overflow-hidden animate-in fade-in zoom-in duration-200">
            <div className="flex justify-between items-center p-6 border-b border-slate-800">
              <h3 className="text-xl font-semibold text-white">Add New User</h3>
              <button onClick={() => setShowAddModal(false)} className="text-slate-400 hover:text-white">
                <X size={20} />
              </button>
            </div>
            <form onSubmit={handleAddUser} className="p-6 space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-400 mb-1">Username</label>
                <input 
                  type="text" 
                  required
                  value={newUsername}
                  onChange={(e) => setNewUsername(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-700 text-white rounded-lg px-4 py-2 focus:outline-none focus:border-blue-500"
                  placeholder="e.g. john_doe"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-400 mb-1">Password</label>
                <input 
                  type="text" 
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-700 text-white rounded-lg px-4 py-2 focus:outline-none focus:border-blue-500"
                  placeholder="Leave empty for random password"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-400 mb-1">Duration (Days)</label>
                <input 
                  type="number" 
                  min="1"
                  required
                  value={newDays}
                  onChange={(e) => setNewDays(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-700 text-white rounded-lg px-4 py-2 focus:outline-none focus:border-blue-500"
                />
              </div>
              <div className="pt-4 flex justify-end gap-3">
                <button 
                  type="button" 
                  onClick={() => setShowAddModal(false)}
                  className="px-4 py-2 text-slate-300 hover:text-white transition-colors"
                >
                  Cancel
                </button>
                <button 
                  type="submit" 
                  className="px-6 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-lg transition-colors font-medium"
                >
                  Create User
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Logs Modal */}
      {showLogs && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="bg-slate-900 border border-slate-800 rounded-xl shadow-2xl w-full max-w-4xl h-[80vh] flex flex-col animate-in fade-in zoom-in duration-200">
            <div className="flex justify-between items-center p-6 border-b border-slate-800">
              <h3 className="text-xl font-semibold text-white flex items-center gap-2">
                <Terminal className="text-blue-500" />
                Service Logs (zivpn.service)
              </h3>
              <div className="flex gap-2">
                <button onClick={fetchLogs} className="p-2 text-slate-400 hover:text-white hover:bg-slate-800 rounded-lg transition-colors" title="Refresh Logs">
                  <RefreshCw size={18} />
                </button>
                <button onClick={() => setShowLogs(false)} className="p-2 text-slate-400 hover:text-white hover:bg-slate-800 rounded-lg transition-colors" title="Close">
                  <X size={20} />
                </button>
              </div>
            </div>
            <div className="p-6 overflow-y-auto flex-1 bg-black/50">
              <pre className="text-xs font-mono text-green-400 whitespace-pre-wrap leading-relaxed">
                {logs || "No logs available."}
              </pre>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}

function MetricCard({ title, value, icon }: { title: string, value: string, icon: React.ReactNode }) {
  return (
    <div className="bg-slate-900 border border-slate-800 p-5 rounded-xl shadow-md flex items-center gap-4">
      <div className="p-3 bg-slate-950 rounded-lg border border-slate-800 shrink-0">
        {icon}
      </div>
      <div className="min-w-0">
        <p className="text-xs font-medium text-slate-400 mb-1 truncate">{title}</p>
        <h3 className="text-lg font-bold text-white truncate" title={value}>{value}</h3>
      </div>
    </div>
  );
}

export default App;