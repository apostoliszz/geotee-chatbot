# 🚀 ΓΕΩΤΕΕ CHATBOT - IMPLEMENTATION GUIDE

## ✅ Completed Files Overview

Έχουν δημιουργηθεί **8 κρίσιμα αρχεία** που έλειπαν από το project:

### 🔴 **HIGH PRIORITY FILES** (4 αρχεία)

1. **`.env.template`** - Environment Variables Template
   - 🔐 Περιέχει όλες τις απαραίτητες μεταβλητές περιβάλλοντος
   - 🔑 Placeholders για passwords, tokens, και API keys
   - ⚙️ Configuration για όλα τα services (Rasa, PostgreSQL, Redis, Qdrant)

2. **`requirements.txt`** - Python Dependencies
   - 📦 Όλα τα Python packages που χρειάζεται το project
   - 🤖 Rasa 3.6.20 και dependencies
   - 🕷️ Scrapy για web scraping
   - 🗄️ Qdrant client και sentence-transformers
   - 📊 FastAPI για analytics

3. **`.gitignore`** - Git Exclusions
   - 🔒 Προστασία sensitive files (.env, credentials, SSL certs)
   - 📁 Exclusion για logs, backups, data files
   - 🐳 Docker volumes και temporary files
   - 🗄️ Database dumps και cache files

4. **`03-deploy.sh`** - Main Deployment Script
   - 🕷️ Web scraping από geotee.gr
   - 🗄️ Vector database indexing στο Qdrant
   - 🤖 Rasa model training
   - 🐳 Docker services orchestration
   - ✅ Health checks
   - 💾 Automated backups

### 🟡 **MEDIUM PRIORITY FILES** (3 αρχεία)

5. **`00-vps-setup.sh`** - VPS Initial Setup
   - 🖥️ System update και optimization
   - 🐍 Python 3.11 installation
   - 🐳 Docker & Docker Compose setup
   - 🌐 Nginx installation
   - 💾 Redis & PostgreSQL setup
   - 🔥 Firewall configuration
   - 🔐 Certbot (Let's Encrypt) installation

6. **`01-project-init.sh`** - Project Initialization
   - 📁 File structure verification
   - ⚙️ .env creation από template
   - 🐍 Virtual environment setup
   - 📦 Python dependencies installation
   - 🤖 Rasa validation
   - 🗄️ Database initialization
   - 🌐 Nginx configuration

7. **`04-monitoring.sh`** - Monitoring & Health Checks
   - 🔧 System services status
   - 🐳 Docker containers health
   - 🏥 Health endpoints check
   - 🗄️ Database status και resource usage
   - 📊 CPU, Memory, Disk monitoring
   - 📈 Analytics summary
   - 💾 Backup status
   - 🔐 SSL certificate check

### 🟢 **LOW PRIORITY FILES** (1 αρχείο)

8. **`05-test-chatbot.sh`** - Automated Testing
   - 🔌 Connectivity tests
   - 🎯 Intent recognition tests
   - ❓ FAQ tests
   - 🔍 Knowledge base search tests
   - 🇬🇷 Language restriction tests
   - ⏱️ Rate limiting tests
   - 📝 Response format tests
   - 🤷 Fallback tests
   - 📊 Analytics tests
   - 🗄️ Vector database tests
   - 💪 Stress tests

---

## 📋 Installation Checklist

### 1️⃣ **Upload Files to VPS**

```bash
# Στο local machine σου (Git Desktop ή terminal):
cd /path/to/geotee-chatbot

# Add τα νέα αρχεία
git add .env.template requirements.txt .gitignore
git add 00-vps-setup.sh 01-project-init.sh 03-deploy.sh
git add 04-monitoring.sh 05-test-chatbot.sh

git commit -m "Add missing core deployment and configuration files"
git push origin main
```

**Ή αν δεν χρησιμοποιείς GitHub ακόμα:**

```bash
# Upload via SCP/SFTP
scp .env.template user@your-vps:/opt/geotee-chatbot/
scp requirements.txt user@your-vps:/opt/geotee-chatbot/
scp .gitignore user@your-vps:/opt/geotee-chatbot/
scp *.sh user@your-vps:/opt/geotee-chatbot/
```

### 2️⃣ **VPS Initial Setup**

```bash
# SSH στο VPS
ssh user@your-vps-ip

# Navigate to project
cd /opt/geotee-chatbot

# Make scripts executable
sudo chmod +x *.sh

# Run VPS setup (ΜΟΝΟ ΜΙΑ ΦΟΡΑ!)
sudo bash 00-vps-setup.sh

# ⏱️ Duration: ~15-20 minutes
```

**Τι κάνει:**
- ✅ System update
- ✅ Installs Python 3.11, Docker, Nginx, Redis, PostgreSQL
- ✅ Configures firewall
- ✅ Installs Certbot
- ✅ Creates project directories
- ✅ Optimizes system settings

### 3️⃣ **Project Initialization**

```bash
# Run project initialization
sudo bash 01-project-init.sh

# ⏱️ Duration: ~10-15 minutes
```

**Τι κάνει:**
- ✅ Verifies file structure
- ✅ Creates .env από template (με auto-generated secrets)
- ✅ Installs Python dependencies
- ✅ Validates Rasa configuration
- ✅ Initializes databases
- ✅ Configures Nginx

### 4️⃣ **Configure Environment**

```bash
# Edit .env file
nano .env

# ⚠️ ΚΡΙΣΙΜΟ: Άλλαξε αυτές τις τιμές:
# - DOMAIN=ai-geotee.cloud (το domain σου)
# - ANALYTICS_USERNAME=admin (username για analytics)
# - Email addresses

# Save: Ctrl+O, Enter, Ctrl+X
```

### 5️⃣ **DNS Configuration**

**Πριν συνεχίσεις, ρύθμισε το DNS:**

```
A Record: ai-geotee.cloud → [VPS IP Address]
```

**Verify DNS:**
```bash
nslookup ai-geotee.cloud
# Πρέπει να επιστρέφει το IP του VPS σου
```

### 6️⃣ **SSL Certificate**

```bash
# Generate SSL certificate (Let's Encrypt)
sudo certbot --nginx -d ai-geotee.cloud

# Copy certificates to deployment folder
sudo cp /etc/letsencrypt/live/ai-geotee.cloud/*.pem \
    /opt/geotee-chatbot/deployment/ssl/

# Set permissions
sudo chmod 644 /opt/geotee-chatbot/deployment/ssl/*.pem
```

### 7️⃣ **Full Deployment**

```bash
# Run the main deployment script
sudo bash 03-deploy.sh

# ⏱️ Duration: ~20-30 minutes
```

**Τι κάνει:**
- 🕷️ Scrapes geotee.gr website
- 🗄️ Creates vector database στο Qdrant
- 🤖 Trains Rasa NLU model
- 🐳 Starts όλα τα Docker services
- ✅ Runs health checks
- 💾 Creates initial backup

### 8️⃣ **Verification**

```bash
# Run monitoring
bash 04-monitoring.sh

# Run automated tests
bash 05-test-chatbot.sh

# Check services
docker-compose -f deployment/docker/docker-compose.yml ps

# Test chatbot manually
curl -X POST http://localhost:5005/webhooks/rest/webhook \
  -H "Content-Type: application/json" \
  -d '{"sender": "test", "message": "γεια σου"}'
```

### 9️⃣ **Access Points**

Μετά από επιτυχημένο deployment:

- 🌐 **Chatbot Widget**: `https://ai-geotee.cloud`
- 📊 **Analytics Dashboard**: `https://ai-geotee.cloud/analytics`
- 📖 **API Documentation**: `https://ai-geotee.cloud/api/docs`
- ❤️ **Health Check**: `https://ai-geotee.cloud/health`

---

## 📊 File Structure Summary

```
geotee-chatbot/
│
├── 📄 .env.template          # ✅ CREATED - Environment variables template
├── 📄 .gitignore            # ✅ CREATED - Git exclusions
├── 📄 requirements.txt      # ✅ CREATED - Python dependencies
│
├── 🔧 00-vps-setup.sh       # ✅ CREATED - VPS initial setup
├── 🔧 01-project-init.sh    # ✅ CREATED - Project initialization
├── 🔧 03-deploy.sh          # ✅ CREATED - Main deployment
├── 🔧 04-monitoring.sh      # ✅ CREATED - Monitoring script
├── 🔧 05-test-chatbot.sh    # ✅ CREATED - Testing script
│
├── scraper/                 # ✅ EXISTS (from previous chat)
├── rasa_bot/               # ✅ EXISTS (from previous chat)
├── analytics/              # ✅ EXISTS (from previous chat)
├── frontend/               # ✅ EXISTS (from previous chat)
├── deployment/             # ✅ EXISTS (from previous chat)
└── ...
```

---

## ⚠️ Important Notes

### 🔒 **Security**

1. **ΠΟΤΕ μην κάνεις commit το `.env` file στο Git!**
   - Το `.gitignore` το προστατεύει
   - Περιέχει passwords και secrets

2. **Άλλαξε τα default passwords:**
   - PostgreSQL password
   - Analytics dashboard password
   - Rasa token

3. **SSL Certificate Auto-Renewal:**
   ```bash
   # Το certbot θα ανανεώνει αυτόματα
   # Verify:
   sudo certbot renew --dry-run
   ```

### 📝 **Maintenance**

**Daily:**
```bash
bash 04-monitoring.sh  # Check system health
```

**Weekly:**
```bash
# Check low confidence queries
curl https://ai-geotee.cloud/api/low-confidence?days=7 | jq

# Update training data based on user queries
nano rasa_bot/data/nlu.yml

# Retrain model
cd rasa_bot && rasa train
docker-compose restart rasa
```

**Monthly:**
```bash
# Re-scrape website
cd scraper
scrapy crawl geotee -o ../data/scraped_data_$(date +%Y%m%d).json

# Re-index to Qdrant
# (code in 03-deploy.sh)

# Update dependencies
source venv/bin/activate
pip list --outdated
```

### 🐛 **Troubleshooting**

**Services not starting:**
```bash
# Check logs
docker-compose logs -f

# Restart specific service
docker-compose restart rasa

# Restart all
docker-compose restart
```

**High resource usage:**
```bash
# Check stats
docker stats

# Check system
htop
```

**Bot not responding:**
```bash
# Check Rasa logs
docker logs geotee_rasa --tail=50

# Restart Rasa
docker-compose restart rasa rasa-actions
```

---

## 🎯 Next Steps After Installation

1. **✅ Integrate Widget** στο geotee.gr website:
   - Copy code από `INTEGRATION_SNIPPET.html`
   - Add πριν το `</body>` tag

2. **✅ Setup GitHub Actions** για auto-deployment:
   - File already exists: `.github/workflows/deploy.yml`
   - Configure secrets στο GitHub repo

3. **✅ Configure Matomo** (optional):
   - Access: `https://ai-geotee.cloud/matomo`
   - Follow setup wizard

4. **✅ Test thoroughly:**
   ```bash
   bash 05-test-chatbot.sh
   ```

5. **✅ Monitor analytics:**
   - Daily stats: `https://ai-geotee.cloud/analytics`
   - Export reports: `/api/export/csv?days=30`

---

## 📞 Support & Documentation

**Documentation Files:**
- `README.md` - Main documentation
- `COMMANDS_CHEATSHEET.md` - Quick command reference
- `PROJECT_SUMMARY.md` - Executive overview

**Logs Location:**
- Deployment: `/opt/geotee-chatbot/logs/deploy_*.log`
- Application: `docker-compose logs`

**Backup Location:**
- `/opt/geotee-chatbot/backups/`
- Auto-backup: Daily at 02:00

---

## ✅ Verification Checklist

Πριν πας production, verify:

- [ ] Όλα τα services running (docker ps)
- [ ] Health checks pass (bash 04-monitoring.sh)
- [ ] Tests pass (bash 05-test-chatbot.sh)
- [ ] SSL certificate valid
- [ ] DNS pointing correctly
- [ ] Backups working (bash backup.sh)
- [ ] Analytics accessible
- [ ] Chatbot responding correctly
- [ ] Rate limiting working
- [ ] Greek-only mode active

---

## 🎉 You're Ready!

Έχεις τώρα όλα τα αρχεία που χρειάζεσαι για να κάνεις deploy το ΓΕΩΤΕΕ Chatbot!

**Estimated Total Time:** 45-60 minutes (από το μηδέν)

**Questions?** Check:
1. README.md για λεπτομερή documentation
2. COMMANDS_CHEATSHEET.md για quick reference
3. Docker logs: `docker-compose logs -f`

---

**Version:** 1.0  
**Last Updated:** October 2024  
**Status:** ✅ Production Ready
