import { useState, useEffect } from 'react'

function App() {
  const [dbStatus, setDbStatus] = useState('Checking...');

  useEffect(() => {
    // Nginx proxies /api to the backend
    fetch('/api/db-test')
      .then(res => res.json())
      .then(data => {
        if (data.status === 'SUCCESS') {
          setDbStatus('Connected to Database! ✅');
        } else {
          setDbStatus('Database Connection Failed ❌');
        }
      })
      .catch(err => {
        setDbStatus('Backend API unreachable ⚠️');
      });
  }, []);

  return (
    <div style={{ fontFamily: 'sans-serif', textAlign: 'center', marginTop: '50px' }}>
      <h1>K8s Kubernetes App Frontend</h1>
      <p>This is a simple React frontend deployed via Jenkins.</p>
      
      <div style={{ marginTop: '30px', padding: '20px', backgroundColor: '#f0f0f0', display: 'inline-block', borderRadius: '8px' }}>
        <h2>System Status</h2>
        <p><strong>Frontend:</strong> Running</p>
        <p><strong>Backend & Database:</strong> {dbStatus}</p>
      </div>
    </div>
  )
}

export default App
