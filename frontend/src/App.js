import React, { useState, useEffect, useCallback } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import axios from 'axios';

// API configuratie
const api = axios.create({
  baseURL: '/api'
});

const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884d8'];

const LeningenApp = () => {
  const [leningen, setLeningen] = useState([]);
  const [betalingen, setBetalingen] = useState([]);
  const [nieuweLening, setNieuweLening] = useState({
    kredietverstrekker: '',
    type: '',
    startdatum: '',
    einddatum: '',
    bedrag: '',
    rentepercentage: '',
    rentetype: 'Vast',
    status: 'Lopend',
    opmerkingen: ''
  });
  const [nieuweBetaling, setNieuweBetaling] = useState({
    leningId: '',
    datum: '',
    termijnbedrag: '',
    aflossing: '',
    rente: '',
    status: 'Betaald'
  });
  const [activeTab, setActiveTab] = useState('overzicht');
  const [editLeningId, setEditLeningId] = useState(null);
  const [filterJaar, setFilterJaar] = useState(new Date().getFullYear());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [jaaroverzicht, setJaaroverzicht] = useState({});

  useEffect(() => {
    fetchData();
  }, []);

  const fetchJaaroverzicht = async () => {
  try {
    if (process.env.NODE_ENV === 'development') {
      try {
        const response = await api.get(`/jaaroverzicht/${filterJaar}`);
        setJaaroverzicht(response.data);
      } catch (err) {
        console.log('Jaaroverzicht API niet beschikbaar, mock data gebruiken');
        setJaaroverzicht({});
      }
    } else {
      const response = await api.get(`/jaaroverzicht/${filterJaar}`);
      setJaaroverzicht(response.data);
    }
  } catch (err) {
    console.error('Error fetching jaaroverzicht:', err);
  }
};

  useEffect(() => {
    fetchJaaroverzicht();
  }, [fetchJaaroverzicht]);

  const fetchData = async () => {
  try {
    setLoading(true);
    // In ontwikkelingsmodus, gebruik mock data als de API niet beschikbaar is
    if (process.env.NODE_ENV === 'development') {
      try {
        const [leningenRes, betalingenRes] = await Promise.all([
          api.get('/leningen'),
          api.get('/betalingen')
        ]);

        setLeningen(leningenRes.data);
        setBetalingen(betalingenRes.data);
        setError(null);
      } catch (err) {
        console.log('API niet beschikbaar, mock data gebruiken');
        setLeningen([]);
        setBetalingen([]);
        setError(null);
      }
    } else {
      // In productie, normaal gedrag
      const [leningenRes, betalingenRes] = await Promise.all([
        api.get('/leningen'),
        api.get('/betalingen')
      ]);

      setLeningen(leningenRes.data);
      setBetalingen(betalingenRes.data);
      setError(null);
    }
  } catch (err) {
    console.error('Error fetching data:', err);
    setError('Er is een fout opgetreden bij het laden van de gegevens.');
  } finally {
    setLoading(false);
  }
};

  // Formulier handlers
  const handleLeningChange = (e) => {
    const { name, value } = e.target;
    setNieuweLening(prev => ({ ...prev, [name]: value }));
  };

  const handleBetalingChange = (e) => {
    const { name, value } = e.target;
    setNieuweBetaling(prev => ({ ...prev, [name]: value }));
  };

  const voegLeningToe = async (e) => {
    e.preventDefault();
    try {
      const formattedLening = {
        ...nieuweLening,
        bedrag: parseFloat(nieuweLening.bedrag),
        rentepercentage: parseFloat(nieuweLening.rentepercentage)
      };

      if (editLeningId) {
        await api.put(`/leningen/${editLeningId}`, formattedLening);
      } else {
        await api.post('/leningen', formattedLening);
      }
      
      fetchData();
      setNieuweLening({
        kredietverstrekker: '',
        type: '',
        startdatum: '',
        einddatum: '',
        bedrag: '',
        rentepercentage: '',
        rentetype: 'Vast',
        status: 'Lopend',
        opmerkingen: ''
      });
      setEditLeningId(null);
      setActiveTab('overzicht');
    } catch (err) {
      console.error('Error saving lening:', err);
      setError('Er is een fout opgetreden bij het opslaan van de lening.');
    }
  };

  const voegBetalingToe = async (e) => {
    e.preventDefault();
    try {
      const formattedBetaling = {
        ...nieuweBetaling,
        leningId: parseInt(nieuweBetaling.leningId),
        termijnbedrag: parseFloat(nieuweBetaling.termijnbedrag),
        aflossing: parseFloat(nieuweBetaling.aflossing),
        rente: parseFloat(nieuweBetaling.rente)
      };

      await api.post('/betalingen', formattedBetaling);
      fetchData();
      setNieuweBetaling({
        leningId: '',
        datum: '',
        termijnbedrag: '',
        aflossing: '',
        rente: '',
        status: 'Betaald'
      });
      setActiveTab('betalingen');
    } catch (err) {
      console.error('Error saving betaling:', err);
      setError('Er is een fout opgetreden bij het opslaan van de betaling.');
    }
  };

  const verwijderLening = async (id) => {
    if (window.confirm('Weet je zeker dat je deze lening wilt verwijderen?')) {
      try {
        await api.delete(`/leningen/${id}`);
        fetchData();
      } catch (err) {
        console.error('Error deleting lening:', err);
        setError('Er is een fout opgetreden bij het verwijderen van de lening.');
      }
    }
  };

  const verwijderBetaling = async (id) => {
    if (window.confirm('Weet je zeker dat je deze betaling wilt verwijderen?')) {
      try {
        await api.delete(`/betalingen/${id}`);
        fetchData();
      } catch (err) {
        console.error('Error deleting betaling:', err);
        setError('Er is een fout opgetreden bij het verwijderen van de betaling.');
      }
    }
  };

  const bewerkLening = (lening) => {
    setNieuweLening({
      kredietverstrekker: lening.kredietverstrekker,
      type: lening.type,
      startdatum: lening.startdatum,
      einddatum: lening.einddatum,
      bedrag: lening.bedrag.toString(),
      rentepercentage: lening.rentepercentage.toString(),
      rentetype: lening.rentetype,
      status: lening.status,
      opmerkingen: lening.opmerkingen || ''
    });
    setEditLeningId(lening.id);
    setActiveTab('nieuweLening');
  };

  // Berekeningen voor dashboards en grafieken
  const berekendBetalingsoverzicht = useCallback(() => {
    const maandenData = [];
    const huidigJaar = filterJaar;

    for (let maand = 0; maand < 12; maand++) {
      const maandBetalingen = betalingen.filter(betaling => {
        const betalingDatum = new Date(betaling.datum);
        return betalingDatum.getFullYear() === huidigJaar && betalingDatum.getMonth() === maand;
      });

      const totaalAflossing = maandBetalingen.reduce((sum, betaling) => sum + betaling.aflossing, 0);
      const totaalRente = maandBetalingen.reduce((sum, betaling) => sum + betaling.rente, 0);

      maandenData.push({
        name: new Date(huidigJaar, maand, 1).toLocaleDateString('nl-NL', { month: 'short' }),
        aflossing: totaalAflossing,
        rente: totaalRente,
        totaal: totaalAflossing + totaalRente
      });
    }

    return maandenData;
  }, [betalingen, filterJaar]);

  const berekendLeningVerdeling = useCallback(() => {
    return leningen.map(lening => ({
      name: lening.kredietverstrekker,
      value: lening.bedrag
    }));
  }, [leningen]);

  if (loading) {
    return <div className="flex justify-center items-center h-screen">Gegevens laden...</div>;
  }

  if (error) {
    return (
      <div className="flex justify-center items-center h-screen bg-red-50">
        <div className="text-red-500 text-center p-6">
          <h2 className="text-xl font-bold mb-2">Fout</h2>
          <p>{error}</p>
          <button 
            className="mt-4 bg-red-500 text-white px-4 py-2 rounded hover:bg-red-600"
            onClick={fetchData}
          >
            Probeer opnieuw
          </button>
        </div>
      </div>
    );
  }

  // Tab inhoud componenten
  const Overzicht = () => (
    <div>
      <h2 className="text-xl font-bold mb-4">Overzicht Leningen</h2>
      <div className="overflow-x-auto">
        <table className="min-w-full bg-white border">
          <thead>
            <tr className="bg-gray-100">
              <th className="py-2 px-4 border">Kredietverstrekker</th>
              <th className="py-2 px-4 border">Type</th>
              <th className="py-2 px-4 border">Startdatum</th>
              <th className="py-2 px-4 border">Einddatum</th>
              <th className="py-2 px-4 border">Bedrag</th>
              <th className="py-2 px-4 border">Rente %</th>
              <th className="py-2 px-4 border">Status</th>
              <th className="py-2 px-4 border">Acties</th>
            </tr>
          </thead>
          <tbody>
            {leningen.map(lening => (
              <tr key={lening.id} className="hover:bg-gray-50">
                <td className="py-2 px-4 border">{lening.kredietverstrekker}</td>
                <td className="py-2 px-4 border">{lening.type}</td>
                <td className="py-2 px-4 border">{new Date(lening.startdatum).toLocaleDateString('nl-NL')}</td>
                <td className="py-2 px-4 border">{new Date(lening.einddatum).toLocaleDateString('nl-NL')}</td>
                <td className="py-2 px-4 border text-right">€ {lening.bedrag.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</td>
                <td className="py-2 px-4 border text-right">{lening.rentepercentage.toFixed(2)}%</td>
                <td className="py-2 px-4 border">
                  <span className={`px-2 py-1 rounded text-xs ${lening.status === 'Lopend' ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'}`}>
                    {lening.status}
                  </span>
                </td>
                <td className="py-2 px-4 border">
                  <div className="flex space-x-2">
                    <button 
                      onClick={() => bewerkLening(lening)} 
                      className="bg-blue-500 text-white px-2 py-1 rounded text-xs hover:bg-blue-600"
                    >
                      Bewerken
                    </button>
                    <button 
                      onClick={() => verwijderLening(lening.id)} 
                      className="bg-red-500 text-white px-2 py-1 rounded text-xs hover:bg-red-600"
                    >
                      Verwijderen
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );

  const NieuweLening = () => (
    <div>
      <h2 className="text-xl font-bold mb-4">{editLeningId ? 'Lening Bewerken' : 'Nieuwe Lening Toevoegen'}</h2>
      <form onSubmit={voegLeningToe} className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Kredietverstrekker</label>
          <input
            type="text"
            name="kredietverstrekker"
            value={nieuweLening.kredietverstrekker}
            onChange={handleLeningChange}
            className="border p-2 rounded"
            required
          />
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Type</label>
          <select
            name="type"
            value={nieuweLening.type}
            onChange={handleLeningChange}
            className="border p-2 rounded"
            required
          >
            <option value="">Selecteer type</option>
            <option value="Hypotheek">Hypotheek</option>
            <option value="Persoonlijke lening">Persoonlijke lening</option>
            <option value="Zakelijke lening">Zakelijke lening</option>
            <option value="Familielening">Familielening</option>
          </select>
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Startdatum</label>
          <input
            type="date"
            name="startdatum"
            value={nieuweLening.startdatum}
            onChange={handleLeningChange}
            className="border p-2 rounded"
            required
          />
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Einddatum</label>
          <input
            type="date"
            name="einddatum"
            value={nieuweLening.einddatum}
            onChange={handleLeningChange}
            className="border p-2 rounded"
            required
          />
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Bedrag (€)</label>
          <input
            type="number"
            name="bedrag"
            value={nieuweLening.bedrag}
            onChange={handleLeningChange}
            className="border p-2 rounded"
            min="0"
            step="0.01"
            required
          />
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Rentepercentage (%)</label>
          <input
            type="number"
            name="rentepercentage"
            value={nieuweLening.rentepercentage}
            onChange={handleLeningChange}
            className="border p-2 rounded"
            min="0"
            step="0.01"
            required
          />
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Rentetype</label>
          <select
            name="rentetype"
            value={nieuweLening.rentetype}
            onChange={handleLeningChange}
            className="border p-2 rounded"
            required
          >
            <option value="Vast">Vast</option>
            <option value="Variabel">Variabel</option>
          </select>
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Status</label>
          <select
            name="status"
            value={nieuweLening.status}
            onChange={handleLeningChange}
            className="border p-2 rounded"
            required
          >
            <option value="Lopend">Lopend</option>
            <option value="Afgelost">Afgelost</option>
            <option value="In aanvraag">In aanvraag</option>
          </select>
        </div>
        <div className="flex flex-col md:col-span-2">
          <label className="mb-1 font-medium">Opmerkingen</label>
          <textarea
            name="opmerkingen"
            value={nieuweLening.opmerkingen}
            onChange={handleLeningChange}
            className="border p-2 rounded"
            rows="3"
          />
        </div>
        <div className="md:col-span-2 flex justify-end space-x-2 mt-4">
          <button
            type="button"
            onClick={() => {
              setNieuweLening({
                kredietverstrekker: '',
                type: '',
                startdatum: '',
                einddatum: '',
                bedrag: '',
                rentepercentage: '',
                rentetype: 'Vast',
                status: 'Lopend',
                opmerkingen: ''
              });
              setEditLeningId(null);
            }}
            className="bg-gray-300 px-4 py-2 rounded hover:bg-gray-400"
          >
            Annuleren
          </button>
          <button 
            type="submit" 
            className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600"
          >
            {editLeningId ? 'Bijwerken' : 'Toevoegen'}
          </button>
        </div>
      </form>
    </div>
  );

  const Betalingen = () => (
    <div>
      <h2 className="text-xl font-bold mb-4">Betalingen Registreren</h2>
      <form onSubmit={voegBetalingToe} className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Lening</label>
          <select
            name="leningId"
            value={nieuweBetaling.leningId}
            onChange={handleBetalingChange}
            className="border p-2 rounded"
            required
          >
            <option value="">Selecteer lening</option>
            {leningen.map(lening => (
              <option key={lening.id} value={lening.id}>
                {lening.kredietverstrekker} - {lening.type} (€{lening.bedrag.toLocaleString('nl-NL')})
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Datum</label>
          <input
            type="date"
            name="datum"
            value={nieuweBetaling.datum}
            onChange={handleBetalingChange}
            className="border p-2 rounded"
            required
          />
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Termijnbedrag (€)</label>
          <input
            type="number"
            name="termijnbedrag"
            value={nieuweBetaling.termijnbedrag}
            onChange={handleBetalingChange}
            className="border p-2 rounded"
            min="0"
            step="0.01"
            required
          />
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Aflossing (€)</label>
          <input
            type="number"
            name="aflossing"
            value={nieuweBetaling.aflossing}
            onChange={handleBetalingChange}
            className="border p-2 rounded"
            min="0"
            step="0.01"
            required
          />
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Rente (€)</label>
          <input
            type="number"
            name="rente"
            value={nieuweBetaling.rente}
            onChange={handleBetalingChange}
            className="border p-2 rounded"
            min="0"
            step="0.01"
            required
          />
        </div>
        <div className="flex flex-col">
          <label className="mb-1 font-medium">Status</label>
          <select
            name="status"
            value={nieuweBetaling.status}
            onChange={handleBetalingChange}
            className="border p-2 rounded"
            required
          >
            <option value="Betaald">Betaald</option>
            <option value="Ingepland">Ingepland</option>
            <option value="Te laat">Te laat</option>
          </select>
        </div>
        <div className="md:col-span-2 flex justify-end space-x-2 mt-4">
          <button
            type="button"
            onClick={() => {
              setNieuweBetaling({
                leningId: '',
                datum: '',
                termijnbedrag: '',
                aflossing: '',
                rente: '',
                status: 'Betaald'
              });
            }}
            className="bg-gray-300 px-4 py-2 rounded hover:bg-gray-400"
          >
            Annuleren
          </button>
          <button 
            type="submit" 
            className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600"
          >
            Toevoegen
          </button>
        </div>
      </form>

      <h3 className="text-lg font-bold mt-8 mb-4">Recente Betalingen</h3>
      <div className="overflow-x-auto">
        <table className="min-w-full bg-white border">
          <thead>
            <tr className="bg-gray-100">
              <th className="py-2 px-4 border">Datum</th>
              <th className="py-2 px-4 border">Lening</th>
              <th className="py-2 px-4 border">Termijnbedrag</th>
              <th className="py-2 px-4 border">Aflossing</th>
              <th className="py-2 px-4 border">Rente</th>
              <th className="py-2 px-4 border">Status</th>
              <th className="py-2 px-4 border">Acties</th>
            </tr>
          </thead>
          <tbody>
            {betalingen.slice().sort((a, b) => new Date(b.datum) - new Date(a.datum)).slice(0, 10).map(betaling => {
              const gekoppeldeLening = leningen.find(l => l.id === betaling.leningId) || { kredietverstrekker: 'Onbekend', type: '' };
              return (
                <tr key={betaling.id} className="hover:bg-gray-50">
                  <td className="py-2 px-4 border">{new Date(betaling.datum).toLocaleDateString('nl-NL')}</td>
                  <td className="py-2 px-4 border">{gekoppeldeLening.kredietverstrekker} - {gekoppeldeLening.type}</td>
                  <td className="py-2 px-4 border text-right">€ {betaling.termijnbedrag.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</td>
                  <td className="py-2 px-4 border text-right">€ {betaling.aflossing.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</td>
                  <td className="py-2 px-4 border text-right">€ {betaling.rente.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</td>
                  <td className="py-2 px-4 border">
                    <span className={`px-2 py-1 rounded text-xs ${
                      betaling.status === 'Betaald' ? 'bg-green-100 text-green-800' : 
                      betaling.status === 'Te laat' ? 'bg-red-100 text-red-800' : 
                      'bg-yellow-100 text-yellow-800'
                    }`}>
                      {betaling.status}
                    </span>
                  </td>
                  <td className="py-2 px-4 border">
                    <button 
                      onClick={() => verwijderBetaling(betaling.id)} 
                      className="bg-red-500 text-white px-2 py-1 rounded text-xs hover:bg-red-600"
                    >
                      Verwijderen
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );

  const Jaaroverzicht = () => (
    <div>
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-xl font-bold">Jaaroverzicht {filterJaar}</h2>
        <div className="flex items-center space-x-2">
          <button 
            onClick={() => setFilterJaar(filterJaar - 1)}
            className="bg-gray-200 p-2 rounded hover:bg-gray-300"
          >
            &lt;
          </button>
          <select 
            value={filterJaar}
            onChange={(e) => setFilterJaar(parseInt(e.target.value))}
            className="border p-2 rounded"
          >
            {Array.from({ length: 10 }, (_, i) => new Date().getFullYear() - 5 + i).map(jaar => (
              <option key={jaar} value={jaar}>{jaar}</option>
            ))}
          </select>
          <button 
            onClick={() => setFilterJaar(filterJaar + 1)}
            className="bg-gray-200 p-2 rounded hover:bg-gray-300"
          >
            &gt;
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <div className="bg-blue-50 p-4 rounded-lg border border-blue-100">
          <h3 className="text-sm text-blue-700 mb-2">Totaal Aflossingen</h3>
          <p className="text-2xl font-bold">
            € {jaaroverzicht.totaalAflossing?.toLocaleString('nl-NL', { minimumFractionDigits: 2 }) || '0,00'}
          </p>
        </div>
        <div className="bg-green-50 p-4 rounded-lg border border-green-100">
          <h3 className="text-sm text-green-700 mb-2">Totaal Rente Betaald</h3>
          <p className="text-2xl font-bold">
            € {jaaroverzicht.totaalRente?.toLocaleString('nl-NL', { minimumFractionDigits: 2 }) || '0,00'}
          </p>
        </div>
        <div className="bg-purple-50 p-4 rounded-lg border border-purple-100">
          <h3 className="text-sm text-purple-700 mb-2">Aantal Betalingen</h3>
          <p className="text-2xl font-bold">
            {jaaroverzicht.aantalBetalingen || 0}
          </p>
        </div>
        <div className="bg-yellow-50 p-4 rounded-lg border border-yellow-100">
          <h3 className="text-sm text-yellow-700 mb-2">Openstaande Leningen</h3>
          <p className="text-2xl font-bold">
            {leningen.filter(l => l.status === 'Lopend').length || 0}
          </p>
        </div>
      </div>

      <div className="bg-white rounded-lg border p-4 mb-8">
        <h3 className="text-lg font-semibold mb-4">Aflossing vs. Rente per Maand</h3>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart
            data={berekendBetalingsoverzicht()}
            margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
          >
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="name" />
            <YAxis />
            <Tooltip formatter={(value) => `€ ${value.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}`} />
            <Legend />
            <Line type="monotone" dataKey="aflossing" name="Aflossing" stroke="#8884d8" activeDot={{ r: 8 }} />
            <Line type="monotone" dataKey="rente" name="Rente" stroke="#82ca9d" />
            <Line type="monotone" dataKey="totaal" name="Totaal" stroke="#ff7300" />
          </LineChart>
        </ResponsiveContainer>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-white rounded-lg border p-4">
          <h3 className="text-lg font-semibold mb-4">Verdeling Leningen</h3>
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie
                data={berekendLeningVerdeling()}
                cx="50%"
                cy="50%"
                labelLine={false}
                outerRadius={100}
                fill="#8884d8"
                dataKey="value"
                label={({ name, percent }) => `${name}: ${(percent * 100).toFixed(0)}%`}
              >
                {berekendLeningVerdeling().map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                ))}
              </Pie>
              <Tooltip formatter={(value) => `€ ${value.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}`} />
            </PieChart>
          </ResponsiveContainer>
        </div>
        
        <div className="bg-white rounded-lg border p-4">
          <h3 className="text-lg font-semibold mb-4">Specificaties per Lening</h3>
          <div className="overflow-y-auto max-h-64">
            <table className="min-w-full bg-white">
              <thead className="bg-gray-50">
                <tr>
                  <th className="py-2 px-4 text-left">Lening</th>
                  <th className="py-2 px-4 text-right">Aflossing {filterJaar}</th>
                  <th className="py-2 px-4 text-right">Rente {filterJaar}</th>
                </tr>
              </thead>
              <tbody>
                {leningen.map(lening => {
                  const leningBetalingen = betalingen.filter(b => 
                    b.leningId === lening.id && 
                    new Date(b.datum).getFullYear() === filterJaar
                  );
                  
                  const totaalAflossing = leningBetalingen.reduce((sum, b) => sum + b.aflossing, 0);
                  const totaalRente = leningBetalingen.reduce((sum, b) => sum + b.rente, 0);
                  
                  return (
                    <tr key={lening.id} className="hover:bg-gray-50 border-b">
                      <td className="py-2 px-4">{lening.kredietverstrekker}</td>
                      <td className="py-2 px-4 text-right">€ {totaalAflossing.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</td>
                      <td className="py-2 px-4 text-right">€ {totaalRente.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );

  const Dashboard = () => {
    const maandenData = berekendBetalingsoverzicht();
    const totaalAflossing = maandenData.reduce((sum, month) => sum + month.aflossing, 0);
    const totaalRente = maandenData.reduce((sum, month) => sum + month.rente, 0);
    const totaalBedragLeningen = leningen.reduce((sum, lening) => sum + lening.bedrag, 0);
    const aantalBetalingenHuidigJaar = betalingen.filter(b => new Date(b.datum).getFullYear() === filterJaar).length;
    
    return (
      <div>
        <h2 className="text-xl font-bold mb-6">Dashboard</h2>
        
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <div className="bg-gradient-to-r from-blue-500 to-blue-600 text-white p-4 rounded-lg">
            <h3 className="text-sm opacity-80 mb-2">Totaal Leenbedrag</h3>
            <p className="text-2xl font-bold">€ {totaalBedragLeningen.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</p>
          </div>
          <div className="bg-gradient-to-r from-green-500 to-green-600 text-white p-4 rounded-lg">
            <h3 className="text-sm opacity-80 mb-2">Aflossing {filterJaar}</h3>
            <p className="text-2xl font-bold">€ {totaalAflossing.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</p>
          </div>
          <div className="bg-gradient-to-r from-red-500 to-red-600 text-white p-4 rounded-lg">
            <h3 className="text-sm opacity-80 mb-2">Rente {filterJaar}</h3>
            <p className="text-2xl font-bold">€ {totaalRente.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</p>
          </div>
          <div className="bg-gradient-to-r from-purple-500 to-purple-600 text-white p-4 rounded-lg">
            <h3 className="text-sm opacity-80 mb-2">Betalingen {filterJaar}</h3>
            <p className="text-2xl font-bold">{aantalBetalingenHuidigJaar}</p>
          </div>
        </div>
        
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <div className="bg-white rounded-lg border p-6">
            <h3 className="text-lg font-semibold mb-4">Betalingen per Maand in {filterJaar}</h3>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart
                data={maandenData}
                margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
              >
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="name" />
                <YAxis />
                <Tooltip formatter={(value) => `€ ${value.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}`} />
                <Legend />
                <Line type="monotone" dataKey="aflossing" name="Aflossing" stroke="#8884d8" />
                <Line type="monotone" dataKey="rente" name="Rente" stroke="#82ca9d" />
              </LineChart>
            </ResponsiveContainer>
          </div>
          
          <div className="bg-white rounded-lg border p-6">
            <h3 className="text-lg font-semibold mb-4">Verdeling Leningen</h3>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={berekendLeningVerdeling()}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  outerRadius={100}
                  fill="#8884d8"
                  dataKey="value"
                  label={({ name, percent }) => `${name}: ${(percent * 100).toFixed(0)}%`}
                >
                  {berekendLeningVerdeling().map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip formatter={(value) => `€ ${value.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}`} />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </div>
        
        <div className="bg-white rounded-lg border p-6">
          <h3 className="text-lg font-semibold mb-4">Samenvatting Leningen</h3>
          <div className="overflow-x-auto">
            <table className="min-w-full bg-white">
              <thead className="bg-gray-50">
                <tr>
                  <th className="py-3 px-4 text-left">Kredietverstrekker</th>
                  <th className="py-3 px-4 text-right">Bedrag</th>
                  <th className="py-3 px-4 text-right">Rente %</th>
                  <th className="py-3 px-4 text-center">Startdatum</th>
                  <th className="py-3 px-4 text-center">Einddatum</th>
                  <th className="py-3 px-4 text-right">Aflossing YTD</th>
                  <th className="py-3 px-4 text-right">Rente YTD</th>
                </tr>
              </thead>
              <tbody>
                {leningen.map(lening => {
                  const leningBetalingen = betalingen.filter(b => 
                    b.leningId === lening.id && 
                    new Date(b.datum).getFullYear() === filterJaar
                  );
                  
                  const totaalAflossing = leningBetalingen.reduce((sum, b) => sum + b.aflossing, 0);
                  const totaalRente = leningBetalingen.reduce((sum, b) => sum + b.rente, 0);
                  
                  return (
                    <tr key={lening.id} className="hover:bg-gray-50 border-b">
                      <td className="py-3 px-4">{lening.kredietverstrekker}</td>
                      <td className="py-3 px-4 text-right">€ {lening.bedrag.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</td>
                      <td className="py-3 px-4 text-right">{lening.rentepercentage.toFixed(2)}%</td>
                      <td className="py-3 px-4 text-center">{new Date(lening.startdatum).toLocaleDateString('nl-NL')}</td>
                      <td className="py-3 px-4 text-center">{new Date(lening.einddatum).toLocaleDateString('nl-NL')}</td>
                      <td className="py-3 px-4 text-right">€ {totaalAflossing.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</td>
                      <td className="py-3 px-4 text-right">€ {totaalRente.toLocaleString('nl-NL', { minimumFractionDigits: 2 })}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    );
  };

  // Tabinhoud object bijwerken met de echte componenten
  const tabInhoud = {
    overzicht: <Overzicht />,
    nieuweLening: <NieuweLening />,
    betalingen: <Betalingen />,
    jaaroverzicht: <Jaaroverzicht />,
    dashboard: <Dashboard />
  };

  return (
    <div className="min-h-screen bg-gray-100 p-4">
      <div className="max-w-6xl mx-auto bg-white rounded-lg shadow-md p-6">
        <h1 className="text-2xl font-bold text-center mb-6 text-blue-800">BV Leningen Beheer</h1>

        <div className="flex flex-wrap mb-6 border-b">
          {['overzicht', 'nieuweLening', 'betalingen', 'jaaroverzicht', 'dashboard'].map((tab) => (
            <button
              key={tab}
              className={`px-4 py-2 mr-2 ${activeTab === tab ? 'bg-blue-500 text-white' : 'bg-gray-200'} rounded-t-lg`}
              onClick={() => setActiveTab(tab)}
            >
              {tab.charAt(0).toUpperCase() + tab.slice(1)}
            </button>
          ))}
        </div>

        <div className="mt-4">
          {tabInhoud[activeTab] || <p>Ongeldige tab</p>}
        </div>
      </div>
    </div>
  );
};

export default LeningenApp;