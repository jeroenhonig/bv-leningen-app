module.exports = {
  apps: [{
    name: 'leningen-backend',
    script: 'server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '150M',
    node_args: '--max-old-space-size=128',
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000,
      DB_HOST: 'localhost',
      DB_PORT: '5432',
      DB_NAME: 'leningen_db',
      DB_USER: 'leningen_user',
      DB_PASSWORD: 'leningen_pass'
    }
  }]
};