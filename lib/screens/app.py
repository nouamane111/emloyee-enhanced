# app.py
from flask import Flask, request, jsonify
from flask_cors import CORS
import psycopg2
from datetime import datetime, timedelta, timezone
from werkzeug.security import generate_password_hash, check_password_hash
from psycopg2.extras import RealDictCursor

# ✅ ADD THESE NEW IMPORTS
from flask_jwt_extended import (
    JWTManager, 
    create_access_token, 
    jwt_required, 
    get_jwt_identity,
    get_jwt
)

# ----------------------------------------
# App
# ----------------------------------------
app = Flask(__name__)
CORS(app)

# ============================================================
# ✅ JWT CONFIGURATION (ADD THIS)
# ============================================================
app.config['JWT_SECRET_KEY'] = 'PMI-LEAP-2025-SECRET-KEY-CHANGE-IN-PRODUCTION-XYZ789'
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(hours=8)  # Token expires after 8 hours
app.config['JWT_TOKEN_LOCATION'] = ['headers']

jwt = JWTManager(app)
# ============================================================
# ----------------------------------------
# DB
# ----------------------------------------
def get_db_connection():
    return psycopg2.connect(
        host="localhost",
        database="ems_db",
        user="postgres",
        password="nouamane",
        port=5433
    )
def current_user_claims():
    """Get user info from JWT token (source of truth)"""
    claims = get_jwt()
    return {
        "username": get_jwt_identity(),
        "role": (claims.get("role") or "").strip(),
        "subrole": (claims.get("subrole") or "").strip(),
        "position": (claims.get("position") or "").strip().lower(),
    }

def is_admin_user():
    """Check if current user is admin"""
    user = current_user_claims()
    return user["role"].lower() == "admin" or user["position"] == "all"

def require_admin():
    """Require admin access (returns error if not admin)"""
    if not is_admin_user():
        return jsonify({"error": "Forbidden: admin access required"}), 403
    return None

def get_current_profile_id(cur):
    """Get profile ID of logged-in user"""
    user = current_user_claims()
    username = (user["username"] or "").strip().lower()
    
    cur.execute("""
        SELECT id FROM profiles 
        WHERE LOWER(TRIM(full_name)) = %s 
        LIMIT 1
    """, (username,))
    row = cur.fetchone()
    
    if row:
        return row[0]
    
    cur.execute("""
        SELECT id FROM users 
        WHERE LOWER(TRIM(username)) = %s 
        LIMIT 1
    """, (username,))
    row = cur.fetchone()
    
    return row[0] if row else None

def can_access_profile(cur, target_profile_id):
    """
    Central hierarchy permission check.

    Admin:
      - Can access everything.

    Channel Manager:
      - Can access all profiles in the same department/category.
      - Cannot access assessed Channel Managers.

    National Supervisor:
      - Can access only profiles under their national_supervisor_id.
      - Cannot access assessed National Supervisors or Channel Managers.

    Supervisor:
      - Can access only Sales Experts under their supervisor_id.
    """
    if is_admin_user():
        return True

    user = current_user_claims()
    user_role = (user["role"] or "").strip().upper()
    position = (user["position"] or "").strip().lower()

    current_profile_id = get_current_profile_id(cur)

    if not current_profile_id:
        return False

    cur.execute("""
        SELECT
            id,
            role,
            channel_manager_id,
            national_supervisor_id,
            supervisor_id,
            LOWER(position)
        FROM profiles
        WHERE id = %s
        LIMIT 1
    """, (target_profile_id,))

    row = cur.fetchone()

    if not row:
        return False

    target_id, target_role, cm_id, ns_id, sup_id, target_pos = row

    target_role = (target_role or "").strip().upper()
    target_pos = (target_pos or "").strip().lower()

    if position == "channel manager":
        return target_role == user_role and target_pos != "channel manager"

    if position == "national supervisor":
        return (
            ns_id == current_profile_id
            and target_pos not in ("national supervisor", "channel manager")
        )

    if position == "supervisor":
        return sup_id == current_profile_id and target_pos == "sales expert"

    return False

# ----------------------------------------
# Helpers (time parsing, filters, etc.)
# ----------------------------------------
# =========================
# Helpers used by /reports/team
# =========================
from datetime import datetime, timedelta, timezone

def _iso_to_utc_any(s: str | None):
    if not s:
        return None
    try:
        s = s.strip()
        if s.endswith("Z"):
            s = s.replace("Z", "+00:00")
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).replace(microsecond=0)
    except Exception:
        return None

def _parse_range_any(body: dict, default_days: int = 30) -> tuple[datetime, datetime]:
    now = datetime.now(timezone.utc).replace(microsecond=0)
    dfrom = _iso_to_utc_any(body.get("date_from")) or now - timedelta(days=default_days)
    dto   = _iso_to_utc_any(body.get("date_to")) or now
    if dfrom > dto:
        dfrom = dto - timedelta(days=default_days)
    return dfrom, dto

def _hierarchy_where(body: dict):
    """
    Restrict by who is asking, like your previous build_reports_where.
    Uses position + ids if provided. Falls back to '1=1'.
    Returns (sql, params)
    """
    clauses, params = [], []
    ch = body.get("channel_manager_id")
    pos = (body.get("position") or "").strip().lower()
    ns  = body.get("national_supervisor_id")
    sp  = body.get("supervisor_id")

    # Profiles alias is p in queries below
    if pos == "all":
        clauses.append("1=1")
    elif pos == "channel manager" and ch:
        clauses.append("p.channel_manager_id = %s"); params.append(ch)
    elif pos == "national supervisor" and ns:
        clauses.append("p.national_supervisor_id = %s"); params.append(ns)
    elif pos == "supervisor" and sp:
        clauses.append("p.supervisor_id = %s"); params.append(sp)
    else:
        clauses.append("1=1")  # default open; adjust if you want stricter default

    return " AND ".join(clauses), params

def _role_filters(body: dict):
    """
    Build WHERE for role/subrole/position/zone + include_unassigned flags.
    Returns (sql_fragment, params)
    """
    clauses, params = [], []
    rf  = (body.get("role_filter") or "").strip()
    srf = (body.get("subrole_filter") or "").strip()
    pf  = (body.get("position_filter") or "").strip()
    zf  = (body.get("zone") or "").strip()

    inc_subrole  = bool(body.get("include_unassigned_subrole", True))
    inc_position = bool(body.get("include_unassigned_position", True))

    if rf:
        clauses.append("p.role = %s"); params.append(rf)

    if srf:
        if inc_subrole:
            clauses.append("(p.subrole = %s OR p.subrole IS NULL OR p.subrole = '')")
            params.append(srf)
        else:
            clauses.append("p.subrole = %s"); params.append(srf)

    if pf:
        if inc_position:
            clauses.append("(LOWER(p.position) = LOWER(%s) OR p.position IS NULL OR p.position = '')")
            params.append(pf)
        else:
            clauses.append("LOWER(p.position) = LOWER(%s)"); params.append(pf)

    if zf:
        clauses.append("p.zone = %s"); params.append(zf)

    return " AND ".join(clauses), params



def _iso_to_utc(dt_str: str | None) -> datetime | None:
    """Parse ISO-8601 to timezone-aware UTC or return None."""
    if not dt_str:
        return None
    try:
        s = dt_str.strip()
        if s.endswith('Z'):
            dt = datetime.fromisoformat(s.replace('Z', '+00:00'))
        else:
            dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None

def _parse_range(body: dict, default_days: int = 30) -> tuple[datetime, datetime]:
    """
    Read date_from/date_to from JSON body.
    If missing/invalid, fall back to [now-default_days, now].
    Always returns (start_utc, end_utc).
    """
    now = datetime.now(timezone.utc)
    start = _iso_to_utc(body.get('date_from')) or (now - timedelta(days=default_days))
    end   = _iso_to_utc(body.get('date_to'))   or now
    if start > end:
        start = end - timedelta(days=default_days)
    return start.replace(microsecond=0), end.replace(microsecond=0)

def _role_filters(body: dict) -> tuple[str, list]:
    """
    Build WHERE fragment + params for role/subrole/position from body.
    Uses profiles alias p in SQL.
    """
    role     = (body.get("role") or "").strip().upper()
    subrole  = (body.get("subrole") or "").strip()
    position = (body.get("position") or "").strip().lower()

    clauses: list[str] = []
    params:  list      = []

    if role:
        clauses.append("UPPER(p.role) = %s")
        params.append(role)
    if subrole:
        clauses.append("LOWER(p.subrole) = LOWER(%s)")
        params.append(subrole)
    if position:
        clauses.append("LOWER(p.position) = LOWER(%s)")
        params.append(position)

    return " AND ".join(clauses), params

def parse_iso(dt):
    """Accept 'YYYY-MM-DD' or full ISO, return naive datetime or None."""
    if not dt:
        return None
    s = str(dt).replace('Z', '')
    try:
        return datetime.fromisoformat(s)
    except Exception:
        try:
            return datetime.strptime(s, "%Y-%m-%d")
        except Exception:
            return None

def build_time_window(data, default_days=180):
    date_from = parse_iso(data.get('date_from'))
    date_to = parse_iso(data.get('date_to'))
    if not date_to:
        date_to = datetime.utcnow()
    if not date_from:
        date_from = date_to - timedelta(days=default_days)
    return date_from, date_to

def build_hierarchy_filters(position, ch_id, ns_id, s_id):
    clauses, params = [], []
    pos = (position or '').lower()
    if pos == "all":  # Admin
        clauses.append("1=1")
    elif pos == 'channel manager':
        clauses.append("p.channel_manager_id = %s"); params.append(ch_id)
    elif pos == "national supervisor":
        clauses.append("p.national_supervisor_id = %s"); params.append(ns_id)
    elif pos == "supervisor":
        clauses.append("p.supervisor_id = %s"); params.append(s_id)
    else:
        clauses.append("1=0")
    return " AND ".join(clauses), params

def apply_optional_role_filters(data, base_where, params):
    rf = data.get("role_filter")
    srf = data.get("subrole_filter")
    pf = data.get("position_filter")
    zf = data.get("zone")
    where = base_where
    if rf:  where += " AND p.role = %s";      params.append(rf)
    if srf: where += " AND p.subrole = %s";   params.append(srf)
    if pf:  where += " AND p.position = %s";  params.append(pf)
    if zf:  where += " AND p.zone = %s";      params.append(zf)
    return where, params

def parse_time_range(label: str):
    """Frontend labels -> (date_from, date_to) UTC (legacy helper)."""
    now = datetime.utcnow()
    if not label:
        return now - timedelta(days=30), now
    lab = label.lower().strip()
    if '7' in lab:
        return now - timedelta(days=7), now
    if '30' in lab:
        return now - timedelta(days=30), now
    if '3 month' in lab or '3months' in lab:
        return now - timedelta(days=90), now
    if 'year' in lab:
        return now - timedelta(days=365), now
    return now - timedelta(days=30), now

def build_reports_where(position, ch_id, ns_id, s_id, extra=None):
    clauses, params = [], []
    pos = (position or '').lower()
    if pos == 'all':
        clauses.append("1=1")
    elif pos == 'channel manager':
        clauses.append("p.channel_manager_id = %s"); params.append(ch_id)
    elif pos == 'national supervisor':
        clauses.append("p.national_supervisor_id = %s"); params.append(ns_id)
    elif pos == 'supervisor':
        clauses.append("p.supervisor_id = %s"); params.append(s_id)
    else:
        clauses.append("1=0")
    if extra:
        clauses.extend(extra)
    return " AND ".join(clauses), params

def apply_department_filter(dept, where, params):
    if dept and dept.lower() != 'all departments':
        where += " AND p.subrole = %s"
        params.append(dept)
    return where, params
@app.route('/reports/person_filter_options', methods=['POST'])
@jwt_required()
def reports_person_filter_options():
    data = request.get_json() or {}
    profile_id = data.get('profile_id')

    if not profile_id:
        return jsonify({
            "status": "error",
            "message": "profile_id required"
        }), 400

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        profile_id = int(profile_id)

        # Important hierarchy/security check
        if not can_access_profile(cur, profile_id):
            return jsonify({
                "status": "error",
                "message": "Forbidden: you cannot access this profile"
            }), 403

        # Categories answered by this employee only
        cur.execute("""
            SELECT DISTINCT
                TRIM(aco.category_title) AS category_title
            FROM assessment_category_outcome aco
            JOIN assessments a ON a.id = aco.assessment_id
            WHERE a.assessee_id = %s
              AND a.completed_at IS NOT NULL
              AND aco.category_title IS NOT NULL
              AND TRIM(aco.category_title) <> ''
            ORDER BY TRIM(aco.category_title)
        """, (profile_id,))

        categories = [row[0] for row in cur.fetchall()]

        # Templates completed by this employee only
        cur.execute("""
            SELECT DISTINCT
                t.id,
                t.name
            FROM assessments a
            JOIN assessmenttemplates t ON t.id = a.template_id
            WHERE a.assessee_id = %s
              AND a.completed_at IS NOT NULL
            ORDER BY t.name
        """, (profile_id,))

        templates = [
            {
                "id": row[0],
                "name": row[1]
            }
            for row in cur.fetchall()
        ]

        return jsonify({
            "status": "success",
            "categories": categories,
            "templates": templates
        }), 200

    except Exception as e:
        print("❌ /reports/person_filter_options:", e)
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

    finally:
        cur.close()
        conn.close()

@app.route('/reports/filter_options', methods=['POST'])
@jwt_required()
def reports_filter_options():
    """
    Role-aware report dropdown/search options.
    Returns only allowed employees and teams.
    Also returns controlled comparison roles/subroles.
    """
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    try:
        user = current_user_claims()
        position = user["position"]
        user_role = (user["role"] or "").strip().upper()
        is_admin = is_admin_user()

        # Resolve logged-in profile id using a normal cursor-safe query
        current_profile_id = None
        if not is_admin:
            username = (user["username"] or "").strip().lower()

            cur.execute("""
                SELECT id
                FROM profiles
                WHERE LOWER(TRIM(full_name)) = %s
                LIMIT 1
            """, (username,))
            row = cur.fetchone()

            if row:
                current_profile_id = row["id"]
            else:
                cur.execute("""
                    SELECT id
                    FROM users
                    WHERE LOWER(TRIM(username)) = %s
                    LIMIT 1
                """, (username,))
                row = cur.fetchone()
                current_profile_id = row["id"] if row else None

            if not current_profile_id:
                return jsonify({
                    "status": "error",
                    "message": "Current profile not found"
                }), 403

        # ---------------- EMPLOYEES ----------------
        if is_admin:
            cur.execute("""
                SELECT id, full_name, position, role, subrole, zone
                FROM profiles
                WHERE LOWER(position) <> 'channel manager'
                ORDER BY full_name
            """)
            employees = [dict(r) for r in cur.fetchall()]

        elif position == "channel manager":
            cur.execute("""
                SELECT id, full_name, position, role, subrole, zone
                FROM profiles
                WHERE UPPER(role) = %s
                  AND LOWER(position) <> 'channel manager'
                ORDER BY full_name
            """, (user_role,))
            employees = [dict(r) for r in cur.fetchall()]

        elif position == "national supervisor":
            cur.execute("""
                SELECT id, full_name, position, role, subrole, zone
                FROM profiles
                WHERE national_supervisor_id = %s
                  AND LOWER(position) NOT IN ('channel manager', 'national supervisor')
                ORDER BY full_name
            """, (current_profile_id,))
            employees = [dict(r) for r in cur.fetchall()]

        elif position == "supervisor":
            cur.execute("""
                SELECT id, full_name, position, role, subrole, zone
                FROM profiles
                WHERE supervisor_id = %s
                  AND LOWER(position) = 'sales expert'
                ORDER BY full_name
            """, (current_profile_id,))
            employees = [dict(r) for r in cur.fetchall()]

        else:
            employees = []

        # ---------------- TEAMS = SUPERVISOR TEAMS ----------------
        if is_admin:
            cur.execute("""
                SELECT id, full_name, position, role, subrole, zone
                FROM profiles
                WHERE LOWER(position) = 'supervisor'
                ORDER BY full_name
            """)
            teams = [dict(r) for r in cur.fetchall()]

        elif position == "channel manager":
            cur.execute("""
                SELECT id, full_name, position, role, subrole, zone
                FROM profiles
                WHERE LOWER(position) = 'supervisor'
                  AND UPPER(role) = %s
                ORDER BY full_name
            """, (user_role,))
            teams = [dict(r) for r in cur.fetchall()]

        elif position == "national supervisor":
            cur.execute("""
                SELECT id, full_name, position, role, subrole, zone
                FROM profiles
                WHERE LOWER(position) = 'supervisor'
                  AND national_supervisor_id = %s
                ORDER BY full_name
            """, (current_profile_id,))
            teams = [dict(r) for r in cur.fetchall()]

        else:
            teams = []

        # ---------------- ROLES ----------------
        roles = ["SFP", "CC", "CE"] if is_admin else []

        # ---------------- SUBROLES / SEGMENTS ----------------
        subroles = []

        if is_admin:
            cur.execute("""
                SELECT DISTINCT
                    CASE
                        WHEN UPPER(role) IN ('CC', 'CE') THEN UPPER(role)
                        ELSE UPPER(TRIM(subrole))
                    END AS segment
                FROM profiles
                WHERE role IS NOT NULL
                  AND TRIM(role) <> ''
                  AND (
                    subrole IS NOT NULL
                    OR UPPER(role) IN ('CC', 'CE')
                  )
                ORDER BY segment
            """)
            subroles = [
                r["segment"] for r in cur.fetchall()
                if r["segment"] and r["segment"] not in ("ALL", "N/A")
            ]

            # Make sure business segments exist even if current data is light
            for forced in ["DIRECT RETAIL", "INDIRECT RETAIL", "LAMP", "CC", "CE"]:
                if forced not in subroles:
                    subroles.append(forced)

        elif position == "channel manager":
            cur.execute("""
                SELECT DISTINCT UPPER(TRIM(subrole)) AS segment
                FROM profiles
                WHERE UPPER(role) = %s
                  AND subrole IS NOT NULL
                  AND TRIM(subrole) <> ''
                ORDER BY segment
            """, (user_role,))
            subroles = [
                r["segment"] for r in cur.fetchall()
                if r["segment"] and r["segment"] not in ("ALL", "N/A")
            ]

            if user_role == "SFP":
                for forced in ["DIRECT RETAIL", "INDIRECT RETAIL", "LAMP"]:
                    if forced not in subroles:
                        subroles.append(forced)

        return jsonify({
            "status": "success",
            "employees": employees,
            "teams": teams,
            "subroles": sorted(set(subroles)),
            "roles": roles,
            "categories": [],
            "templates": []
        }), 200

    except Exception as e:
        print("❌ /reports/filter_options:", e)
        return jsonify({"status": "error", "message": str(e)}), 500

    finally:
        cur.close()
        conn.close()
# ==============================================================================
# ROUTE 2: /reports/person_trend
# Get trend data for one person (overall / category / template)
# ==============================================================================
 
@app.route('/reports/person_trend', methods=['POST'])
@jwt_required()
def reports_person_trend():
    """
    Get trend analysis for one person.
    Modes: overall, category, template
    """
    try:
        data = request.get_json() or {}
        
        profile_id = data.get('profile_id')
        trend_type = data.get('trend_type', 'overall')  # overall, category, template
        category_title = data.get('category_title')
        template_id = data.get('template_id')
        date_from = data.get('date_from')
        date_to = data.get('date_to')
        
        if not profile_id:
            return jsonify({'status': 'error', 'message': 'profile_id required'}), 400
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # ==============================================
        # MODE A: OVERALL TREND (all assessments)
        # ==============================================
        if trend_type == 'overall':
            query = """
                SELECT 
                    a.id,
                    a.completed_at::date as assessment_date,
                    a.final_score,
                    t.name as template_name
                FROM assessments a
                LEFT JOIN assessmenttemplates t ON a.template_id = t.id
                WHERE a.assessee_id = %s
                  AND a.completed_at IS NOT NULL
            """
            params = [profile_id]
            
            if date_from:
                query += " AND a.completed_at >= %s"
                params.append(date_from)
            if date_to:
                query += " AND a.completed_at <= %s"
                params.append(date_to)
            
            query += " ORDER BY a.completed_at"
            
            cur.execute(query, params)
            rows = cur.fetchall()
            
            trend = []
            for row in rows:
                trend.append({
                    'date': str(row['assessment_date']),
                    'score': float(row['final_score']) if row['final_score'] else 0.0,
                    'template': row['template_name']
                })
        
        # ==============================================
        # MODE B: CATEGORY TREND (one category over time)
        # ==============================================
        elif trend_type == 'category':
            if not category_title:
                return jsonify({'status': 'error', 'message': 'category_title required for category trend'}), 400
            
            query = """
                SELECT 
                    a.id,
                    a.completed_at::date as assessment_date,
                    aco.avg_score,
                    aco.category_title,
                    t.name as template_name
                FROM assessments a
                JOIN assessment_category_outcome aco ON a.id = aco.assessment_id
                LEFT JOIN assessmenttemplates t ON a.template_id = t.id
                WHERE a.assessee_id = %s
                    AND LOWER(TRIM(aco.category_title)) = LOWER(TRIM(%s))
                    AND a.completed_at IS NOT NULL
            """
            params = [profile_id, category_title]
            
            if date_from:
                query += " AND a.completed_at >= %s"
                params.append(date_from)
            if date_to:
                query += " AND a.completed_at <= %s"
                params.append(date_to)
            
            query += " ORDER BY a.completed_at"
            
            cur.execute(query, params)
            rows = cur.fetchall()
            
            trend = []
            for row in rows:
                # avg_score is already stored as /3.0 scale
                score_on_3 = float(row['avg_score']) if row['avg_score'] else 0.0
                
                trend.append({
                    'date': str(row['assessment_date']),
                    'score': score_on_3,
                    'template': row['template_name']
                })
        
        # ==============================================
        # MODE C: TEMPLATE TREND (one template over time)
        # ==============================================
        elif trend_type == 'template':
            if not template_id:
                return jsonify({'status': 'error', 'message': 'template_id required for template trend'}), 400
            
            query = """
                SELECT 
                    a.id,
                    a.completed_at::date as assessment_date,
                    a.final_score,
                    t.name as template_name
                FROM assessments a
                LEFT JOIN assessmenttemplates t ON a.template_id = t.id
                WHERE a.assessee_id = %s
                  AND a.template_id = %s
                  AND a.completed_at IS NOT NULL
            """
            params = [profile_id, template_id]
            
            if date_from:
                query += " AND a.completed_at >= %s"
                params.append(date_from)
            if date_to:
                query += " AND a.completed_at <= %s"
                params.append(date_to)
            
            query += " ORDER BY a.completed_at"
            
            cur.execute(query, params)
            rows = cur.fetchall()
            
            trend = []
            for row in rows:
                trend.append({
                    'date': str(row['assessment_date']),
                    'score': float(row['final_score']) if row['final_score'] else 0.0,
                    'template': row['template_name']
                })
        
        else:
            return jsonify({'status': 'error', 'message': 'Invalid trend_type'}), 400
        
        # ==============================================
        # CALCULATE SUMMARY STATS
        # ==============================================
        summary = {
            'first_score': None,
            'latest_score': None,
            'change': 0.0,
            'status': 'No data',
            'count': len(trend)
        }
        
        if trend:
            first_score = trend[0]['score']
            latest_score = trend[-1]['score']
            change = latest_score - first_score
            
            summary['first_score'] = first_score
            summary['latest_score'] = latest_score
            summary['change'] = round(change, 2)
            
            if change > 0.2:
                summary['status'] = 'Improving'
            elif change < -0.2:
                summary['status'] = 'Declining'
            else:
                summary['status'] = 'Stable'
        
        cur.close()
        conn.close()
        
        return jsonify({
            'status': 'success',
            'trend': trend,
            'summary': summary
        }), 200
        
    except Exception as e:
        print(f"Error in person_trend: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500
 
 
# ==============================================================================
# ROUTE 3: /reports/comparison_trend
# Compare two entities (person vs person, team vs team, etc.)
# ==============================================================================
 
@app.route('/reports/comparison_trend', methods=['POST'])
@jwt_required()
def reports_comparison_trend():
    """
    Compare two entities.
    Types:
      - person
      - team
      - subrole/segment
      - role
    """
    data = request.get_json() or {}

    comparison_type = data.get('comparison_type')
    left_id = data.get('left_id')
    right_id = data.get('right_id')
    left_value = (data.get('left_value') or '').strip()
    right_value = (data.get('right_value') or '').strip()
    date_from = data.get('date_from')
    date_to = data.get('date_to')

    if not comparison_type:
        return jsonify({'status': 'error', 'message': 'comparison_type required'}), 400

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    try:
        user = current_user_claims()
        position = user["position"]
        user_role = (user["role"] or "").strip().upper()

        def segment_condition(value):
            value_up = (value or "").strip().upper()

            if value_up in ("SFP", "CC", "CE"):
                return "UPPER(p.role) = %s", [value_up]

            return "UPPER(TRIM(p.subrole)) = %s", [value_up]

        def apply_date_filter(query, params):
            if date_from:
                query += " AND a.completed_at >= %s"
                params.append(date_from)
            if date_to:
                query += " AND a.completed_at <= %s"
                params.append(date_to)
            return query, params

        def security_scope_for_profiles():
            """
            Extra security for comparison.
            Admin: no extra restriction.
            Channel Manager: same role except Channel Managers.
            National Supervisor: own downline, no NS/CM.
            Supervisor: own Sales Experts.
            """
            if is_admin_user():
                return "", []

            current_profile_id = get_current_profile_id(conn.cursor())

            if not current_profile_id:
                return " AND 1=0", []

            if position == "channel manager":
                return """
                    AND UPPER(p.role) = %s
                    AND LOWER(p.position) <> 'channel manager'
                """, [user_role]

            if position == "national supervisor":
                return """
                    AND p.national_supervisor_id = %s
                    AND LOWER(p.position) NOT IN ('national supervisor', 'channel manager')
                """, [current_profile_id]

            if position == "supervisor":
                return """
                    AND p.supervisor_id = %s
                    AND LOWER(p.position) = 'sales expert'
                """, [current_profile_id]

            return " AND 1=0", []

        security_sql, security_params = security_scope_for_profiles()

        def get_entity_trend(entity_type, entity_id=None, entity_value=None):
            if entity_type == 'person':
                # Access check
                check_cur = conn.cursor()
                allowed = can_access_profile(check_cur, int(entity_id))
                check_cur.close()

                if not allowed:
                    return []

                query = """
                    SELECT
                        a.completed_at::date AS assessment_date,
                        a.final_score
                    FROM assessments a
                    JOIN profiles p ON p.id = a.assessee_id
                    WHERE a.assessee_id = %s
                      AND a.completed_at IS NOT NULL
                """
                params = [entity_id]

            elif entity_type == 'team':
                query = """
                    SELECT
                        a.completed_at::date AS assessment_date,
                        AVG(a.final_score) AS final_score
                    FROM assessments a
                    JOIN profiles p ON p.id = a.assessee_id
                    WHERE p.supervisor_id = %s
                      AND a.completed_at IS NOT NULL
                """
                params = [entity_id]
                query += security_sql
                params.extend(security_params)

            elif entity_type == 'subrole':
                condition_sql, condition_params = segment_condition(entity_value)

                query = f"""
                    SELECT
                        a.completed_at::date AS assessment_date,
                        AVG(a.final_score) AS final_score
                    FROM assessments a
                    JOIN profiles p ON p.id = a.assessee_id
                    WHERE {condition_sql}
                      AND a.completed_at IS NOT NULL
                """
                params = condition_params
                query += security_sql
                params.extend(security_params)

            elif entity_type == 'role':
                if not is_admin_user():
                    return []

                query = """
                    SELECT
                        a.completed_at::date AS assessment_date,
                        AVG(a.final_score) AS final_score
                    FROM assessments a
                    JOIN profiles p ON p.id = a.assessee_id
                    WHERE UPPER(p.role) = %s
                      AND a.completed_at IS NOT NULL
                """
                params = [(entity_value or "").strip().upper()]

            else:
                return []

            query, params = apply_date_filter(query, params)

            if entity_type in ['team', 'subrole', 'role']:
                query += " GROUP BY a.completed_at::date"

            query += " ORDER BY assessment_date"

            cur.execute(query, params)
            rows = cur.fetchall()

            return [{
                'date': str(row['assessment_date']),
                'score': float(row['final_score']) if row['final_score'] is not None else 0.0
            } for row in rows]

        if comparison_type == 'person':
            if not left_id or not right_id:
                return jsonify({'status': 'error', 'message': 'left_id and right_id required'}), 400

            cur.execute("SELECT full_name FROM profiles WHERE id = %s", (left_id,))
            left_row = cur.fetchone()
            left_name = left_row['full_name'] if left_row else f"Person {left_id}"

            cur.execute("SELECT full_name FROM profiles WHERE id = %s", (right_id,))
            right_row = cur.fetchone()
            right_name = right_row['full_name'] if right_row else f"Person {right_id}"

            left_trend = get_entity_trend('person', entity_id=left_id)
            right_trend = get_entity_trend('person', entity_id=right_id)

        elif comparison_type == 'team':
            if not left_id or not right_id:
                return jsonify({'status': 'error', 'message': 'left_id and right_id required'}), 400

            cur.execute("SELECT full_name FROM profiles WHERE id = %s", (left_id,))
            left_row = cur.fetchone()
            left_name = f"{left_row['full_name']} Team" if left_row else f"Team {left_id}"

            cur.execute("SELECT full_name FROM profiles WHERE id = %s", (right_id,))
            right_row = cur.fetchone()
            right_name = f"{right_row['full_name']} Team" if right_row else f"Team {right_id}"

            left_trend = get_entity_trend('team', entity_id=left_id)
            right_trend = get_entity_trend('team', entity_id=right_id)

        elif comparison_type == 'subrole':
            if not left_value or not right_value:
                return jsonify({'status': 'error', 'message': 'left_value and right_value required'}), 400

            left_name = left_value
            right_name = right_value
            left_trend = get_entity_trend('subrole', entity_value=left_value)
            right_trend = get_entity_trend('subrole', entity_value=right_value)

        elif comparison_type == 'role':
            if not left_value or not right_value:
                return jsonify({'status': 'error', 'message': 'left_value and right_value required'}), 400

            if not is_admin_user():
                return jsonify({'status': 'error', 'message': 'Role comparison is admin-only'}), 403

            left_name = left_value.upper()
            right_name = right_value.upper()
            left_trend = get_entity_trend('role', entity_value=left_value)
            right_trend = get_entity_trend('role', entity_value=right_value)

        else:
            return jsonify({'status': 'error', 'message': 'Invalid comparison_type'}), 400

        def change_of(trend):
            if len(trend) < 2:
                return 0.0
            return round(trend[-1]['score'] - trend[0]['score'], 2)

        def avg_of(trend):
            if not trend:
                return 0.0
            return round(sum(t['score'] for t in trend) / len(trend), 2)

        left_change = change_of(left_trend)
        right_change = change_of(right_trend)
        left_avg = avg_of(left_trend)
        right_avg = avg_of(right_trend)

        if left_change > right_change:
            winner = left_name
            insight = f"{left_name} improved faster ({left_change:+.2f}) than {right_name} ({right_change:+.2f})."
        elif right_change > left_change:
            winner = right_name
            insight = f"{right_name} improved faster ({right_change:+.2f}) than {left_name} ({left_change:+.2f})."
        else:
            winner = "Tie"
            insight = f"Both sides show the same change ({left_change:+.2f})."

        return jsonify({
            'status': 'success',
            'left': {
                'label': left_name,
                'trend': left_trend
            },
            'right': {
                'label': right_name,
                'trend': right_trend
            },
            'summary': {
                'left_label': left_name,
                'right_label': right_name,
                'winner': winner,
                'left_change': left_change,
                'right_change': right_change,
                'left_avg': left_avg,
                'right_avg': right_avg,
                'insight': insight
            }
        }), 200

    except Exception as e:
        print("❌ /reports/comparison_trend:", e)
        return jsonify({'status': 'error', 'message': str(e)}), 500

    finally:
        cur.close()
        conn.close()

# ----------------------------------------
# PROFILE ROUTES
# ----------------------------------------
@app.route('/add_profile', methods=['POST'])
@jwt_required()
def add_profile():
    data = request.json


    admin_error = require_admin()
    if admin_error:
        return admin_error

    role = (data.get('role') or '').strip()                       # 'Admin' | 'SFP' | 'CC' | 'CE'
    subrole = (data.get('subrole') or '').strip()
    position = (data.get('position') or '').strip()               # 'Sales expert' | 'Supervisor' | ...
    full_name = (data.get('full_name') or '').strip()
    username = (data.get('username') or '').strip() if data.get('username') else None
    password = (data.get('password') or '').strip() if data.get('password') else None
    supervisor_name = (data.get('supervisor_name') or '').strip() if data.get('supervisor_name') else None
    national_supervisor_name = (data.get('national_supervisor_name') or '').strip() if data.get('national_supervisor_name') else None
    zone = (data.get('zone') or '').strip()                       # REQUIRED
    date_joined = (data.get('date_joined') or '').strip() or None # OPTIONAL: 'YYYY-MM-DD'

    # Quick server-side validation
    if not role or not subrole or not position or not full_name:
        return jsonify({'error': 'role, subrole, position, and full_name are required'}), 400
    if not zone:
        return jsonify({'error': 'Zone is required'}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    def get_profile_id_by_full_name(name):
        """Look up hierarchy by full_name in profiles (NOT users)."""
        if not name:
            return None
        cur.execute("SELECT id FROM profiles WHERE LOWER(full_name) = LOWER(%s)", (name,))
        r = cur.fetchone()
        return r[0] if r else None

    # Pre-resolve (will validate per-branch below)
    supervisor_id = get_profile_id_by_full_name(supervisor_name)
    national_supervisor_id = get_profile_id_by_full_name(national_supervisor_name)

    try:
        if role == 'Admin':
            if not username or not password:
                conn.rollback()
                return jsonify({'error': 'Admin requires username and password'}), 400

            hashed_password = generate_password_hash(password)

            cur.execute("""
                INSERT INTO users (username, password, role, subrole, position)
                VALUES (%s, %s, 'Admin', 'ALL', 'ALL')
            """, (username, hashed_password))

            cur.execute("""
                INSERT INTO profiles (full_name, role, subrole, position, zone, date_joined)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (full_name, 'Admin', 'ALL', 'ALL', zone, date_joined))
        # ---------------- SFP ----------------
        elif role == 'SFP':
            both_supers_positions = {'Sales expert', 'Brand ambassador', 'Brand representative', 'Brand representatives'}

            if position in both_supers_positions:
                # No account; but must have both supervisor & national supervisor, existing in profiles
                if not supervisor_id or not national_supervisor_id:
                    conn.rollback()
                    return jsonify({'error': f'{position} requires supervisor_name and national_supervisor_name that exist in profiles.full_name.'}), 400

                cur.execute("""
                    INSERT INTO profiles (
                        full_name, role, subrole, position,
                        supervisor_id, national_supervisor_id, zone, date_joined
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """, (full_name, role, subrole, position,
                      supervisor_id, national_supervisor_id, zone, date_joined))

            elif position == 'Supervisor':
                # Requires account + national supervisor
                if not username or not password:
                    conn.rollback()
                    return jsonify({'error': 'SFP Supervisor requires username and password'}), 400
                if not national_supervisor_id:
                    conn.rollback()
                    return jsonify({'error': 'SFP Supervisor requires national_supervisor_name that exists in profiles.full_name.'}), 400

                hashed_password = generate_password_hash(password)

                cur.execute("""
                    INSERT INTO users (username, password, role, subrole, position)
                    VALUES (%s, %s, %s, %s, %s)
                """, (username, hashed_password, role, subrole, position))

                cur.execute("""
                    INSERT INTO profiles (
                        full_name, role, subrole, position,
                        supervisor_id, national_supervisor_id, zone, date_joined
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """, (full_name, role, subrole, position,
                      supervisor_id, national_supervisor_id, zone, date_joined))

            elif position in {'National supervisor', 'Channel manager'}:
                # Requires account; no mandatory hierarchy here
                if not username or not password:
                    conn.rollback()
                    return jsonify({'error': f'SFP {position} requires username and password'}), 400

                hashed_password = generate_password_hash(password)

                cur.execute("""
                    INSERT INTO users (username, password, role, subrole, position)
                    VALUES (%s, %s, %s, %s, %s)
                """, (username, hashed_password, role, subrole, position))

                cur.execute("""
                    INSERT INTO profiles (full_name, role, subrole, position, zone, date_joined)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, (full_name, role, subrole, position, zone, date_joined))

            else:
                conn.rollback()
                return jsonify({'error': f'Unsupported SFP position: {position}'}), 400

        # ---------------- CE ----------------
        elif role == 'CE':
            if position == 'Supervisor':
                if not username or not password:
                    conn.rollback()
                    return jsonify({'error': 'CE Supervisor requires username and password'}), 400

                hashed_password = generate_password_hash(password)

                cur.execute("""
                    INSERT INTO users (username, password, role, subrole, position)
                    VALUES (%s, %s, %s, %s, %s)
                """, (username, hashed_password, role, subrole or 'N/A', position))

                cur.execute("""
                    INSERT INTO profiles (full_name, role, subrole, position, zone, date_joined)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, (full_name, role, subrole, position, zone, date_joined))

            elif position == 'Brand representatives':
                # No account; requires supervisor_name existing (ONLY supervisor)
                if not supervisor_id:
                    conn.rollback()
                    return jsonify({'error': 'CE Brand representatives requires supervisor_name that exists in profiles.full_name.'}), 400

                cur.execute("""
                    INSERT INTO profiles (
                        full_name, role, subrole, position,
                        supervisor_id, zone, date_joined
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                """, (full_name, role, subrole, position,
                    supervisor_id, zone, date_joined))

            else:
                conn.rollback()
                return jsonify({'error': f'Unsupported CE position: {position}'}), 400


        # ---------------- CC ----------------
        elif role == 'CC':
            if position == 'Supervisor':
                if not username or not password:
                    conn.rollback()
                    return jsonify({'error': 'CC Supervisor requires username and password'}), 400

                hashed_password = generate_password_hash(password)

                cur.execute("""
                    INSERT INTO users (username, password, role, subrole, position)
                    VALUES (%s, %s, %s, %s, %s)
                """, (username, hashed_password, role, subrole or 'N/A', position))

                cur.execute("""
                    INSERT INTO profiles (full_name, role, subrole, position, zone, date_joined)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, (full_name, role, subrole, position, zone, date_joined))

            elif position == 'Sales promoters':
                # Account required + both supervisor & national supervisor must exist
                if not username or not password:
                    conn.rollback()
                    return jsonify({'error': 'CC Sales promoters requires username and password'}), 400
                if not supervisor_id or not national_supervisor_id:
                    conn.rollback()
                    return jsonify({'error': 'CC Sales promoters requires supervisor_name and national_supervisor_name that exist in profiles.full_name.'}), 400

                hashed_password = generate_password_hash(password)

                cur.execute("""
                    INSERT INTO users (username, password, role, subrole, position)
                    VALUES (%s, %s, %s, %s, %s)
                """, (username, hashed_password, role, subrole or 'N/A', position))
                cur.execute("""
                    INSERT INTO profiles (
                        full_name, role, subrole, position,
                        supervisor_id, national_supervisor_id, zone, date_joined
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """, (full_name, role, subrole, position,
                      supervisor_id, national_supervisor_id, zone, date_joined))

            else:
                conn.rollback()
                return jsonify({'error': f'Unsupported CC position: {position}'}), 400

        else:
            conn.rollback()
            return jsonify({'error': f'Unsupported role: {role}'}), 400

        conn.commit()
        return jsonify({'message': 'Profile added successfully'}), 200

    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        cur.close()
        conn.close()
# Scoped profiles listing (enforces hierarchy)
# ----------------------------------------


@app.route('/profiles_visible', methods=['GET'])
@jwt_required()
def profiles_visible():
    # ✅ GET FROM JWT TOKEN (Source of truth)
    user = current_user_claims()
    username_raw = user["username"]
    position = user["position"]
    user_role = user["role"]

    # Frontend can still send 'role' as a FILTER (which dept to show)
    force_role = (request.args.get('role') or '').strip().upper()

    # Frontend can send search query
    q = (request.args.get('q') or '').strip()

    # ✅ Admin detection using JWT
    is_admin = (position == 'all') or (user_role.lower() == 'admin')

    like = f"%{q}%"
    try:
        limit = int(request.args.get('limit', 50))
        if limit <= 0 or limit > 200:
            limit = 50
    except Exception:
        limit = 50

    try:
        offset = int(request.args.get('offset', 0))
        if offset < 0:
            offset = 0
    except Exception:
        offset = 0

    order = (request.args.get('order') or 'name').strip().lower()
    position_rank_case = """
      CASE LOWER(position)
        WHEN 'channel manager' THEN 1
        WHEN 'national supervisor' THEN 2
        WHEN 'supervisor' THEN 3
        WHEN 'sales expert' THEN 4
        ELSE 9
      END
    """
    order_sql = "ORDER BY full_name ASC" if order != 'position' else f"ORDER BY {position_rank_case}, full_name ASC"

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        # -------------------- ADMIN-LIKE (no scoping) --------------------
        if is_admin:
            params = []
            where = []

            if force_role in ('SFP', 'CE', 'CC'):
                where.append("role = %s")
                params.append(force_role)

            if q:
                where.append("full_name ILIKE %s")
                params.append(like)

            where_sql = "WHERE " + " AND ".join(where) if where else ""

            # total count
            cur.execute(f"SELECT COUNT(*) FROM profiles {where_sql}", params)
            total = cur.fetchone()[0]

            # page
            cur.execute(f"""
                SELECT id, full_name, role AS category, subrole, position
                FROM profiles
                {where_sql}
                {order_sql}
                LIMIT %s OFFSET %s
            """, (*params, limit, offset))
            rows = cur.fetchall()

            result = [{
                'id': r[0],
                'full_name': r[1],
                'category': r[2],
                'role': r[2],
                'subrole': r[3],
                'position': r[4],
            } for r in rows]

            return jsonify({'profiles': result, 'total': total, 'limit': limit, 'offset': offset}), 200

        # -------------------- Resolve "me" (try profiles then users) --------------------
        username_lc = username_raw.lower()

        cur.execute("""
            SELECT id, role, position
            FROM profiles
            WHERE LOWER(full_name) = %s
            LIMIT 1
        """, (username_lc,))
        me = cur.fetchone()

        if not me:
            # fallback if some managers still live in users table
            try:
                cur.execute("""
                    SELECT id, role, position
                    FROM users
                    WHERE LOWER(username) = %s
                    LIMIT 1
                """, (username_lc,))
                me = cur.fetchone()
            except Exception:
                me = None

        if not me:
            return jsonify({'error': 'user not found'}), 403

        me_id, me_role, me_pos = me
        me_role_eff = (force_role or (me_role or '')).upper()

        # -------------------- Scoped visibility rules --------------------
        params = []
        where = []

        if q:
            where.append("full_name ILIKE %s")
            params.append(like)

        # Always pin to department if we know it
        if me_role_eff in ('SFP', 'CE', 'CC'):
            where.append("role = %s")
            params.append(me_role_eff)

        if position == 'channel manager':
            # Channel Manager sees everyone in their department/category,
            # except other Channel Managers.
            where.append("role = %s")
            params.append(user_role.upper())
            where.append("LOWER(position) <> 'channel manager'")

        elif position == 'national supervisor':
            # National Supervisor sees only supervisors and field profiles under them.
            # They should not see Channel Managers or other National Supervisors.
            where.append("national_supervisor_id = %s")
            params.append(me_id)
            where.append("LOWER(position) NOT IN ('channel manager', 'national supervisor')")

        elif position == 'supervisor':
            # Only their sales experts
            where.append("supervisor_id = %s")
            params.append(me_id)
            # explicitly keep only sales experts in this scope
            where.append("LOWER(position) = 'sales expert'")

        else:
            # Fallback: same spirit as search_profiles — exclude channel managers
            where.append("LOWER(position) <> 'channel manager'")

        where_sql = "WHERE " + " AND ".join(where) if where else ""

        # total count
        cur.execute(f"SELECT COUNT(*) FROM profiles {where_sql}", params)
        total = cur.fetchone()[0]

        # page
        cur.execute(f"""
            SELECT id, full_name, role AS category, subrole, position
            FROM profiles
            {where_sql}
            {order_sql}
            LIMIT %s OFFSET %s
        """, (*params, limit, offset))
        rows = cur.fetchall()

        result = [{
            'id': r[0],
            'full_name': r[1],
            'category': r[2],
            'role': r[2],
            'subrole': r[3],
            'position': r[4],
        } for r in rows]

        return jsonify({'profiles': result, 'total': total, 'limit': limit, 'offset': offset}), 200

    except Exception as e:
        return jsonify({'error': 'internal server error', 'detail': str(e)}), 500
    finally:
        cur.close()
        conn.close()




# ----------------------------------------
# LOGIN + health
# ----------------------------------------
@app.route('/login', methods=['POST'])
def login():
    """
    SECURE LOGIN - Returns JWT token for authentication.
    """
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    if not username or not password:
        return jsonify({
            "success": False, 
            "message": "Username and password required"
        }), 400

    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        cur.execute("SELECT * FROM users WHERE username = %s", (username,))
        user = cur.fetchone()

        if user and check_password_hash(user[2], password):
            # ✅ User found - Create JWT token with user data
            user_data = {
                "username": str(user[1]),
                "role": str(user[3]),
                "subrole": str(user[5]),
                "position": str(user[6])
            }
            
            # ✅ Create JWT access token (expires in 8 hours)
            access_token = create_access_token(
                identity=username,
                additional_claims=user_data
            )
            
            print(f"✅ Login successful: {username}")  # Debug log
            
            return jsonify({
                "success": True,
                "message": "Login successful",
                "access_token": access_token,  # ✅ NEW: JWT token
                "username": str(user[1]),
                "role": str(user[3]),
                "subrole": str(user[5]),
                "position": str(user[6])
            }), 200
        else:
            print(f"❌ Login failed: Invalid credentials for {username}")
            return jsonify({
                "success": False, 
                "message": "Invalid credentials"
            }), 401
            
    except Exception as e:
        print("❌ Login error:", str(e))
        return jsonify({
            "success": False, 
            "message": "Login failed"
        }), 500
    finally:
        cur.close()
        conn.close()

# ----------------------------------------
# Templates
# ----------------------------------------
@app.route('/create_template', methods=['POST'])
@jwt_required()
def create_template():
    data = request.get_json()


    admin_error = require_admin()
    if admin_error:
        return admin_error

    template_name = data.get('templateName')
    description = data.get('description', '')
    created_by = data.get('createdBy', 'Unknown')
    selected_role = data.get('role')
    selected_subrole = data.get('subrole')
    selected_position = data.get('position')
    categories = data.get('categories', [])

    if not template_name or not selected_role:
        return jsonify({'error': 'Template name and role are required'}), 400

    conn = get_db_connection(); cur = conn.cursor()
    try:
        cur.execute("""
            INSERT INTO assessmenttemplates (name, description, created_by, created_at, role, subrole, position)
            VALUES (%s, %s, %s, NOW(), %s, %s, %s)
            RETURNING id
        """, (template_name, description, created_by, selected_role, selected_subrole, selected_position))
        template_id = cur.fetchone()[0]

        for category in categories:
            title = (category.get('title') or '').strip()
            if not title:
                continue
            cur.execute(
                "INSERT INTO assessmentcategories (template_id, title) VALUES (%s, %s) RETURNING id",
                (template_id, title)
            )
            category_id = cur.fetchone()[0]
            for question_text in category.get('questions', []):
                q = (question_text or '').strip()
                if q:
                    cur.execute(
                        "INSERT INTO assessmentquestions (category_id, question_text) VALUES (%s, %s)",
                        (category_id, q)
                    )

        conn.commit()
        return jsonify({'message': 'Template created successfully'}), 201
    except Exception as e:
        conn.rollback()
        print("Error:", str(e))
        return jsonify({'error': str(e)}), 500
    finally:
        cur.close(); conn.close()

@app.route('/delete_profile', methods=['POST'])
@jwt_required()
def delete_profile():
    admin_error = require_admin()
    if admin_error:
        return admin_error

    data = request.get_json() or {}
    profile_id = data.get('id')

    if not profile_id:
        return jsonify({'error': 'Profile id is required'}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Make sure the profile exists first
        cur.execute("""
            SELECT full_name, role, position
            FROM profiles
            WHERE id = %s
        """, (profile_id,))
        profile = cur.fetchone()

        if not profile:
            return jsonify({'error': 'Profile not found'}), 404

        full_name, role, position = profile

        # Delete matching login account if this profile has one.
        # This works because your users.username usually matches profiles.full_name.
        cur.execute("""
            DELETE FROM users
            WHERE LOWER(TRIM(username)) = LOWER(TRIM(%s))
        """, (full_name,))

        # Delete profile.
        # If this profile is referenced by assessments or hierarchy IDs,
        # PostgreSQL may block deletion depending on FK constraints.
        cur.execute("""
            DELETE FROM profiles
            WHERE id = %s
        """, (profile_id,))

        conn.commit()

        return jsonify({
            'status': 'success',
            'message': f'Profile "{full_name}" deleted successfully'
        }), 200

    except Exception as e:
        conn.rollback()
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

    finally:
        cur.close()
        conn.close()

@app.route('/delete_template', methods=['POST'])
@jwt_required()
def delete_template():
    data = request.get_json()


    admin_error = require_admin()
    if admin_error:
        return admin_error


    template_name = data.get('name')
    conn = get_db_connection(); cur = conn.cursor()
    try:
        cur.execute("DELETE FROM assessmenttemplates WHERE name = %s", (template_name,))
        conn.commit()
        return jsonify({'status': 'success', 'message': 'Template deleted'}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        cur.close(); conn.close()

@app.route('/get_assessment_initiate', methods=['POST'])
@jwt_required()
def get_assessment_initiate():
    data = request.get_json()
    template_name = data.get('template_name')

    conn = get_db_connection(); cur = conn.cursor()
    try:
        cur.execute("SELECT id FROM assessmenttemplates WHERE name = %s", (template_name,))
        template_row = cur.fetchone()
        if not template_row:
            return jsonify({"error": "Template not found"}), 404
        template_id = template_row[0]

        cur.execute("""
            SELECT id, title, description
            FROM assessmentcategories
            WHERE template_id = %s
        """, (template_id,))
        category_rows = cur.fetchall()

        categories = []
        for cat_id, title, description in category_rows:
            cur.execute("""
                SELECT id, question_text
                FROM assessmentquestions
                WHERE category_id = %s
            """, (cat_id,))
            question_rows = cur.fetchall()
            questions = [{"id": q[0], "question_text": q[1]} for q in question_rows]
            categories.append({
                "id": cat_id,
                "title": title,
                "description": description,
                "questions": questions
            })

        return jsonify({"template": {"id": template_id, "name": template_name, "categories": categories}}), 200
    except Exception as e:
        print("🔥 Exception in /get_assessment_initiate:", str(e))
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close(); conn.close()


@app.route('/get_templates', methods=['POST'])
@jwt_required()
def get_templates():
    """
    Secure template listing.

    Admin:
      - Sees all templates.

    Channel Manager:
      - Sees templates in their department/category.
      - Cannot see templates targeting Channel Managers.

    National Supervisor:
      - Sees templates in their department/category and subrole.
      - Cannot see templates targeting National Supervisors or Channel Managers.

    Supervisor:
      - Sees only field-level / Sales Expert templates in their department/category and subrole.
    """
    data = request.get_json() or {}

    user = current_user_claims()
    user_role = (user["role"] or "").strip().upper()
    user_subrole = (user["subrole"] or "").strip()
    user_position = (user["position"] or "").strip().lower()

    selected_role = (data.get("role") or "").strip().upper()
    selected_subrole = (data.get("subrole") or "").strip()

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        where_clauses = []
        params = []

        if is_admin_user():
            if selected_role:
                where_clauses.append("UPPER(role) = %s")
                params.append(selected_role)

            if selected_subrole:
                where_clauses.append("LOWER(subrole) = LOWER(%s)")
                params.append(selected_subrole)

        elif user_position == "channel manager":
            where_clauses.append("UPPER(role) = %s")
            params.append(user_role)

            if selected_subrole:
                where_clauses.append("LOWER(subrole) = LOWER(%s)")
                params.append(selected_subrole)

            where_clauses.append("LOWER(position) <> 'channel manager'")

        elif user_position == "national supervisor":
            where_clauses.append("UPPER(role) = %s")
            params.append(user_role)

            if selected_subrole:
                where_clauses.append("LOWER(subrole) = LOWER(%s)")
                params.append(selected_subrole)
            elif user_subrole and user_subrole.upper() != "ALL":
                where_clauses.append("LOWER(subrole) = LOWER(%s)")
                params.append(user_subrole)

            where_clauses.append("""
                LOWER(position) NOT IN ('national supervisor', 'channel manager')
            """)

        elif user_position == "supervisor":
            where_clauses.append("UPPER(role) = %s")
            params.append(user_role)

            if selected_subrole:
                where_clauses.append("LOWER(subrole) = LOWER(%s)")
                params.append(selected_subrole)
            elif user_subrole and user_subrole.upper() != "ALL":
                where_clauses.append("LOWER(subrole) = LOWER(%s)")
                params.append(user_subrole)

            where_clauses.append("""
                LOWER(position) IN (
                    'sales expert',
                    'brand representative',
                    'brand representatives',
                    'brand ambassador',
                    'sales promoters',
                    'promoters'
                )
            """)

        else:
            where_clauses.append("1=0")

        where_sql = "WHERE " + " AND ".join(where_clauses) if where_clauses else ""

        cur.execute(f"""
            SELECT
                name,
                role,
                subrole,
                created_by,
                created_at,
                position
            FROM assessmenttemplates
            {where_sql}
            ORDER BY created_at DESC
        """, params)

        rows = cur.fetchall()

        templates = [{
            "name": r[0],
            "role": r[1],
            "subrole": r[2],
            "created_by": r[3],
            "created_at": r[4].strftime('%Y-%m-%d %H:%M:%S') if r[4] else '',
            "position": r[5]
        } for r in rows]

        return jsonify({'templates': templates}), 200

    except Exception as e:
        print("❌ Error in /get_templates:", str(e))
        return jsonify({'error': str(e)}), 500

    finally:
        cur.close()
        conn.close()


# ----------------------------------------
# Submit assessment
# ----------------------------------------
@app.route('/submit_assessment', methods=['POST'])
@jwt_required()
def submit_assessment():
    data = request.get_json()

# ✅ SECURITY: Get assessor from JWT (can't be faked)
    assessor_username = get_jwt_identity()
    
    # Frontend sends these (we'll validate them)
    assessed_name     = data.get('assessed_name')
    template_name     = data.get('template_name')
    answers           = data.get('answers', [])

    if not (assessed_name and template_name and answers):
        return jsonify({'error': 'Missing required fields'}), 400

    conn = get_db_connection(); cur = conn.cursor()
    try:
        assessor_username = assessor_username.strip().lower()
        assessed_name     = assessed_name.strip().lower()
        template_name     = template_name.strip()

        # Template
        cur.execute("SELECT id, name FROM assessmenttemplates WHERE name = %s", (template_name,))
        trow = cur.fetchone()
        if not trow:
            return jsonify({'error': 'Template not found'}), 404
        template_id, template_name_db = trow[0], trow[1]

        # Assessee (profile)
        cur.execute("SELECT id, full_name FROM profiles WHERE LOWER(TRIM(full_name)) = %s", (assessed_name,))
        prow = cur.fetchone()
        if not prow:
            return jsonify({'error': f'Assessee \"{assessed_name}\" not found'}), 404
        assessee_id, assessee_name_db = prow[0], prow[1]

        # ✅ SECURITY: Check if assessor can assess this person
        if not can_access_profile(cur, assessee_id):
            cur.close()
            conn.close()
            return jsonify({'error': 'Forbidden: you cannot assess this person'}), 403

        # Assessor (user)
        cur.execute("SELECT id FROM users WHERE LOWER(TRIM(username)) = %s", (assessor_username,))
        urow = cur.fetchone()
        if not urow:
            return jsonify({'error': f'Assessor \"{assessor_username}\" not found'}), 404

        # Validate all template questions answered (Oui/Non/Partiellement/N/A)
        cur.execute("""
            SELECT q.id, q.category_id, c.title
            FROM assessmentquestions q
            JOIN assessmentcategories c ON c.id = q.category_id
            WHERE c.template_id = %s
            ORDER BY q.id
        """, (template_id,))
        templ_q = cur.fetchall()

        required_q_ids = {row[0] for row in templ_q}
        answered_q_ids = {int(a['question_id']) for a in answers if a.get('answer') in ('Oui','Non','Partiellement','N/A')}
        missing = sorted(required_q_ids - answered_q_ids)
        if missing:
            return jsonify({
                'error': 'All questions must be answered before submitting.',
                'missing_question_ids': missing
            }), 400

        # Create assessment row
        cur.execute("""
            INSERT INTO assessments (
                template_id, assessor_name, assessee_name, assessee_id,
                started_at, completed_at, final_score, comment
            )
            VALUES (%s, %s, %s, %s, NOW(), NOW(), NULL, '')
            RETURNING id, completed_at
        """, (template_id, assessor_username, assessee_name_db, assessee_id))
        assessment_id, completed_at = cur.fetchone()

        # Insert answers + per-category accumulators
        score_map = {'Oui': 3.0, 'Partiellement': 2.0, 'Non': 1.0, 'N/A': None}
        per_cat = {}
        q_to_cat = {qid: (cid, ctitle) for (qid, cid, ctitle) in templ_q}
        final_pool = []

        for ans in answers:
            qid = int(ans['question_id'])
            response = ans.get('answer')
            comment  = ans.get('comment', '')

            if qid not in q_to_cat:
                return jsonify({'error': f'Question ID {qid} is not in this template'}), 400
            category_id, category_title = q_to_cat[qid]

            score = score_map.get(response)

            cur.execute("""
                INSERT INTO assessmentanswers (
                    assessment_id, question_id, answer, comment, score_obtained, category_id
                ) VALUES (%s, %s, %s, %s, %s, %s)
            """, (assessment_id, qid, response, comment, score, category_id))

            bucket = per_cat.setdefault(category_id, {
                'title': category_title,
                'scores': [],
                'right': 0, 'partial': 0, 'wrong': 0,
                'total_q': 0, 'answered_q': 0
            })
            bucket['total_q'] += 1
            if response in ('Oui','Partiellement','Non'):
                bucket['answered_q'] += 1
                if response == 'Oui':            bucket['right']   += 1
                elif response == 'Partiellement': bucket['partial'] += 1
                elif response == 'Non':          bucket['wrong']   += 1
                if score is not None:
                    bucket['scores'].append(float(score))
                    final_pool.append(float(score))

        final_score = round(sum(final_pool) / len(final_pool), 2) if final_pool else None
        cur.execute("UPDATE assessments SET final_score = %s WHERE id = %s", (final_score, assessment_id))

        # attempt_seq from ACO per (assessee, template)
        cur.execute("""
            SELECT COALESCE(MAX(attempt_seq), 0) + 1
            FROM assessment_category_outcome
            WHERE assessee_id = %s AND template_id = %s
        """, (assessee_id, template_id))
        attempt_seq = cur.fetchone()[0] or 1

        # upsert category outcomes
        for cat_id, acc in per_cat.items():
            avg_sc = round(sum(acc['scores'])/len(acc['scores']), 2) if acc['scores'] else None
            cur.execute("""
                INSERT INTO assessment_category_outcome (
                    assessment_id, assessee_id, assessee_name,
                    template_id, template_name, attempt_seq,
                    category_id, category_title,
                    total_questions, answered_questions,
                    right_count, partial_count, wrong_count,
                    avg_score
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (assessment_id, category_id) DO UPDATE
                SET total_questions = EXCLUDED.total_questions,
                    answered_questions = EXCLUDED.answered_questions,
                    right_count = EXCLUDED.right_count,
                    partial_count = EXCLUDED.partial_count,
                    wrong_count = EXCLUDED.wrong_count,
                    avg_score = EXCLUDED.avg_score
            """, (
                assessment_id, assessee_id, assessee_name_db,
                template_id, template_name_db, attempt_seq,
                cat_id, acc['title'],
                acc['total_q'], acc['answered_q'],
                acc['right'], acc['partial'], acc['wrong'],
                avg_sc
            ))

        conn.commit()
        return jsonify({'message': 'Assessment submitted successfully',
                        'final_score': final_score,
                        'assessment_id': assessment_id,
                        'attempt_seq': attempt_seq}), 200

    except Exception as e:
        conn.rollback()
        print("❌ Error in /submit_assessment:", e)
        return jsonify({'error': str(e)}), 500
    finally:
        cur.close(); conn.close()
# ----------------------------------------
# Visible profiles list (same hierarchy algo as /search_profiles)
# ----------------------------------------


# ----------------------------------------
# Search profiles (typeahead)
# ----------------------------------------
@app.route('/search_profiles', methods=['GET'])
@jwt_required()
def search_profiles():
    """
    Query params:
      - username (required except for admin)
      - position: all | channel manager | national supervisor | supervisor
      - query: text in profiles.full_name
      - role (optional): SFP/CE/CC
      - limit (optional): default 25
    """
# ✅ GET FROM JWT TOKEN (Source of truth)
    user = current_user_claims()
    username_raw = user["username"]
    position = user["position"]
    
    # Frontend sends search query and optional role filter
    q = (request.args.get('query') or '').strip()
    force_role = (request.args.get('role') or '').strip().upper()
    
    # Validation
    if not q:
        return jsonify({'error': 'query is required'}), 400

    like = f"%{q}%"
    try:
        limit = int(request.args.get('limit', 25))
        if limit <= 0 or limit > 200:
            limit = 25
    except Exception:
        limit = 25

    conn = get_db_connection(); cur = conn.cursor()
    try:
        if position == 'all':
            if force_role:
                cur.execute("""
                    SELECT id, full_name, role AS category, subrole, position
                    FROM profiles
                    WHERE role = %s
                      AND full_name ILIKE %s
                    ORDER BY full_name ASC
                    LIMIT %s
                """, (force_role, like, limit))
            else:
                cur.execute("""
                    SELECT id, full_name, role AS category, subrole, position
                    FROM profiles
                    WHERE full_name ILIKE %s
                    ORDER BY full_name ASC
                    LIMIT %s
                """, (like, limit))

            rows = cur.fetchall()
            result = [{
                'id': r[0],
                'full_name': r[1],
                'category': r[2],
                'role': r[2],
                'subrole': r[3],
                'position': r[4],
            } for r in rows]
            return jsonify(result), 200

        username_lc = username_raw.lower()
        cur.execute("""
            SELECT id, role, position
            FROM profiles
            WHERE LOWER(full_name) = %s
            LIMIT 1
        """, (username_lc,))
        me = cur.fetchone()

        if not me:
            cur.execute("""
                SELECT id, role, position
                FROM profiles
                WHERE LOWER(username) = %s
                LIMIT 1
            """, (username_lc,))
            me = cur.fetchone()

        if not me:
            return jsonify({'error': 'user not found'}), 403

        me_id, me_role, me_pos = me
        me_role = (force_role or (me_role or '')).upper()

        if position == 'channel manager':
            cur.execute("""
                SELECT id, full_name, role AS category, subrole, position
                FROM profiles
                WHERE role = %s
                AND full_name ILIKE %s
                AND LOWER(position) <> 'channel manager'
                ORDER BY full_name ASC
                LIMIT %s
            """, (me_role, like, limit))

        elif position == 'national supervisor':
            cur.execute("""
                SELECT id, full_name, role AS category, subrole, position
                FROM profiles
                WHERE role = %s
                AND national_supervisor_id = %s
                AND LOWER(position) NOT IN ('channel manager', 'national supervisor')
                AND full_name ILIKE %s
                ORDER BY full_name ASC
                LIMIT %s
            """, (me_role, me_id, like, limit))

        elif position == 'supervisor':
            cur.execute("""
                SELECT id, full_name, role AS category, subrole, position
                FROM profiles
                WHERE role = %s
                  AND supervisor_id = %s
                  AND full_name ILIKE %s
                ORDER BY full_name ASC
                LIMIT %s
            """, (me_role, me_id, like, limit))

        else:
            cur.execute("""
                SELECT id, full_name, role AS category, subrole, position
                FROM profiles
                WHERE role = %s
                  AND full_name ILIKE %s
                  AND LOWER(position) <> 'channel manager'
                ORDER BY full_name ASC
                LIMIT %s
            """, (me_role, like, limit))

        rows = cur.fetchall()
        result = [{
            'id': r[0],
            'full_name': r[1],
            'category': r[2],
            'role': r[2],
            'subrole': r[3],
            'position': r[4],
        } for r in rows]

        return jsonify(result), 200

    except Exception:
        return jsonify({'error': 'internal server error'}), 500
    finally:
        cur.close(); conn.close()


# ----------------------------------------
# Assessment history/result
# ----------------------------------------
@app.route('/get_assessment_history', methods=['POST'])
@jwt_required()
def get_assessment_history():
    """
    SECURE VERSION - Filters assessments by user hierarchy.
    Only returns assessments the user is authorized to see.
    """
    data = request.json or {}
    
    # ✅ GET FROM JWT TOKEN (Source of truth - can't be faked)
    user = current_user_claims()
    username = user["username"]
    position = user["position"]
    user_role = user["role"]
    
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # ============================================================
        # SECURITY: Build WHERE clause based on user's position
        # ============================================================
        
        if position == 'all':
            # ✅ ADMIN - See everything
            where_clause = "a.completed_at IS NOT NULL"
            where_params = []
            
        else:
            # ✅ NON-ADMIN - Apply hierarchy filtering
            
            # First, get the user's profile ID
            cur.execute("""
                SELECT id FROM profiles 
                WHERE LOWER(TRIM(full_name)) = %s
                LIMIT 1
            """, (username.lower(),))
            user_row = cur.fetchone()
            
            if not user_row:
                # Try fallback to users table
                cur.execute("""
                    SELECT id FROM users 
                    WHERE LOWER(TRIM(username)) = %s
                    LIMIT 1
                """, (username.lower(),))
                user_row = cur.fetchone()
            
            if not user_row:
                return jsonify({
                    'status': 'error', 
                    'message': f'User "{username}" not found'
                }), 403
            
            user_id = user_row[0]
            
            if position == 'channel manager':
                # Channel Manager sees all completed assessments for their department/category.
                # Example: SFP Channel Manager sees all SFP assessment history.
                where_clause = """
                    a.completed_at IS NOT NULL
                    AND p.role = %s
                    AND LOWER(p.position) <> 'channel manager'
                """
                where_params = [user_role.upper()]
                
            elif position == 'national supervisor':
                where_clause = """
                    a.completed_at IS NOT NULL
                    AND p.national_supervisor_id = %s
                    AND LOWER(p.position) NOT IN ('national supervisor', 'channel manager')
                """
                where_params = [user_id]
            elif position == 'supervisor':
                where_clause = """
                    a.completed_at IS NOT NULL
                    AND p.supervisor_id = %s
                    AND LOWER(p.position) = 'sales expert'
                """
                where_params = [user_id]
                
            else:
                # Unknown position - return empty (safe default)
                return jsonify({
                    'status': 'success', 
                    'history': []
                }), 200
        
        # ============================================================
        # Execute SECURE query
        # ============================================================
        query = f"""
            SELECT
                a.id,
                p.full_name AS assessee_name,
                a.assessor_name,
                t.name AS template_name,
                a.final_score,
                a.completed_at,
                p.role AS assessee_role,
                p.subrole AS assessee_subrole,
                p.position AS assessee_position,
                t.subrole AS template_subrole
            FROM assessments a
            LEFT JOIN assessmenttemplates t ON a.template_id = t.id
            LEFT JOIN profiles p ON a.assessee_id = p.id
            WHERE {where_clause}
            ORDER BY a.completed_at DESC
        """
        
        cur.execute(query, where_params)
        rows = cur.fetchall()
        
        cols = ['id','assessee_name','assessor_name','template_name','final_score','completed_at',
                'assessee_role','assessee_subrole','assessee_position','template_subrole']
        history = [dict(zip(cols, r)) for r in rows]
        
        return jsonify({'status': 'success', 'history': history}), 200
        
    except Exception as e:
        print("❌ Error in /get_assessment_history:", str(e))
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        cur.close()
        conn.close()

@app.route("/get_assessment_result", methods=["POST"])
@jwt_required()
def get_assessment_result():
    data = request.get_json()
    assessment_id = data.get("assessment_id")
    if not assessment_id:
        return jsonify({"status": "error", "message": "Assessment ID is required"}), 400

    conn = get_db_connection(); cur = conn.cursor()
        # ✅ SECURITY: Check if user can access this assessment
    cur.execute("""
        SELECT assessee_id 
        FROM assessments 
        WHERE id = %s
    """, (assessment_id,))
    row = cur.fetchone()
    
    if not row:
        cur.close()
        conn.close()
        return jsonify({"status": "error", "message": "Assessment not found"}), 404
    
    assessee_id = row[0]
    
    # ✅ Hierarchy check
    if not can_access_profile(cur, assessee_id):
        cur.close()
        conn.close()
        return jsonify({
            "status": "error", 
            "message": "Forbidden: you cannot access this assessment"
        }), 403
    

    try:
        cur.execute("""
            SELECT a.id, a.assessor_name, a.assessee_name, a.started_at, 
                   a.completed_at, a.final_score, a.comment, t.name as template_name,
                   p.role, p.subrole, p.position
            FROM assessments a
            JOIN assessmenttemplates t ON a.template_id = t.id
            LEFT JOIN profiles p ON a.assessee_id = p.id
            WHERE a.id = %s
        """, (assessment_id,))
        r = cur.fetchone()
        if not r:
            return jsonify({"status": "error", "message": "Assessment not found"}), 404

        assessment_info = {
            "id": r[0], "assessor_name": r[1], "assessee_name": r[2],
            "started_at": r[3].strftime("%Y-%m-%d %H:%M:%S") if r[3] else "",
            "completed_at": r[4].strftime("%Y-%m-%d %H:%M:%S") if r[4] else "",
            "final_score": float(r[5]) if r[5] else 0.0, "comment": r[6] or "",
            "template_name": r[7], "assessee_role": r[8] or "",
            "assessee_subrole": r[9] or "", "assessee_position": r[10] or ""
        }

        cur.execute("SELECT template_id FROM assessments WHERE id = %s", (assessment_id,))
        template_id = cur.fetchone()[0]

        cur.execute("""
            SELECT c.id, c.title, c.description, COUNT(q.id) as total_questions
            FROM assessmentcategories c
            LEFT JOIN assessmentquestions q ON c.id = q.category_id
            WHERE c.template_id = %s
            GROUP BY c.id, c.title, c.description
            ORDER BY c.id
        """, (template_id,))
        category_rows = cur.fetchall()

        categories = []
        total_questions = answered_questions = 0
        total_score = max_possible_score = 0.0

        for category_id, category_title, category_description, _ in category_rows:
            cur.execute("""
                SELECT q.id, q.question_text, ans.answer, ans.comment, ans.score_obtained
                FROM assessmentquestions q
                LEFT JOIN assessmentanswers ans ON (q.id = ans.question_id AND ans.assessment_id = %s)
                WHERE q.category_id = %s
                ORDER BY q.id
            """, (assessment_id, category_id))
            qrows = cur.fetchall()

            questions = []
            category_score = 0.0
            category_answered = 0

            for qid, qtext, answer, comment, score in qrows:
                total_questions += 1
                max_possible_score += 3.0
                if answer and answer != "Not Answered":
                    answered_questions += 1
                    category_answered += 1
                    if score is not None:
                        total_score += float(score)
                        category_score += float(score)

                questions.append({
                    "id": qid, "question_text": qtext,
                    "answer": answer or "Not Answered",
                    "comment": comment or "",
                    "score_obtained": float(score) if score is not None else 0.0,
                    "is_answered": bool(answer and answer != "Not Answered")
                })

            completion_pct = (category_answered / len(qrows) * 100) if qrows else 0
            categories.append({
                "id": category_id, "title": category_title,
                "description": category_description or "",
                "questions": questions,
                "total_questions": len(qrows),
                "answered_questions": category_answered,
                "completion_percentage": round(completion_pct, 1),
                "category_score": round(category_score, 2),
                "max_category_score": len(qrows) * 3.0
            })

        completion_rate = (answered_questions / total_questions * 100) if total_questions > 0 else 0
        score_percentage = (total_score / max_possible_score * 100) if max_possible_score > 0 else 0
        performance_level = get_performance_level(score_percentage)

        assessment_info.update({
            "categories": categories,
            "statistics": {
                "total_questions": total_questions,
                "answered_questions": answered_questions,
                "completion_rate": round(completion_rate, 1),
                "total_score": round(total_score, 2),
                "max_possible_score": round(max_possible_score, 2),
                "score_percentage": round(score_percentage, 1),
                "performance_level": performance_level
            }
        })

        return jsonify({"status": "success", "assessment": assessment_info}), 200
    except Exception as e:
        print(f"🔥 Error in /get_assessment_result: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        cur.close(); conn.close()

def get_performance_level(score_percentage):
    if score_percentage >= 85:
        return "Accelerate"
    elif score_percentage >= 70:
        return "Advanced"
    else:
        return "Inadequate"
    

@app.route('/reports/person_category_breakdown', methods=['POST'])
@jwt_required()
def reports_person_category_breakdown():
    data = request.get_json() or {}
    profile_id = data.get('profile_id')

    if not profile_id:
        return jsonify({'status': 'error', 'message': 'profile_id required'}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        if not can_access_profile(cur, int(profile_id)):
            return jsonify({
                'status': 'error',
                'message': 'Forbidden: you cannot access this profile'
            }), 403

        cur.execute("""
            SELECT
                aco.category_title,
                COALESCE(ROUND(
                    SUM(aco.avg_score * aco.answered_questions)
                    / NULLIF(SUM(aco.answered_questions), 0)
                ::numeric, 2), 0) AS avg_on3,
                COALESCE(SUM(aco.right_count), 0) AS right_count,
                COALESCE(SUM(aco.partial_count), 0) AS partial_count,
                COALESCE(SUM(aco.wrong_count), 0) AS wrong_count,
                COALESCE(SUM(aco.answered_questions), 0) AS answered_questions,
                COALESCE(SUM(aco.total_questions), 0) AS total_questions
            FROM assessment_category_outcome aco
            JOIN assessments a ON a.id = aco.assessment_id
            WHERE a.assessee_id = %s
              AND a.completed_at IS NOT NULL
            GROUP BY aco.category_title
            ORDER BY avg_on3 DESC
        """, (profile_id,))

        rows = cur.fetchall()

        categories = []
        for category, avg_on3, right, partial, wrong, answered, total in rows:
            score_percentage = (float(avg_on3 or 0) / 3.0) * 100
            categories.append({
                "category": category,
                "avg_on3": float(avg_on3 or 0),
                "score_percentage": round(score_percentage, 1),
                "performance_level": get_performance_level(score_percentage),
                "right": int(right or 0),
                "partial": int(partial or 0),
                "wrong": int(wrong or 0),
                "answered": int(answered or 0),
                "total": int(total or 0)
            })

        return jsonify({
            "status": "success",
            "categories": categories
        }), 200

    except Exception as e:
        print("❌ /reports/person_category_breakdown:", e)
        return jsonify({"status": "error", "message": str(e)}), 500

    finally:
        cur.close()
        conn.close()


@app.route('/get_profile_details', methods=['POST'])
@jwt_required()
def get_profile_details():
    data = request.get_json()
    profile_id = data.get('profile_id')
    if not profile_id:
        return jsonify({'error': 'Missing profile_id'}), 400

    conn = get_db_connection(); cur = conn.cursor()

        # ✅ SECURITY: Check if user can access this profile
    if not can_access_profile(cur, int(profile_id)):
        cur.close()
        conn.close()
        return jsonify({'error': 'Forbidden: you cannot access this profile'}), 403
    

    cur.execute("""
        SELECT full_name, email, phone, role, subrole, position
        FROM profiles WHERE id = %s
    """, (profile_id,))
    profile = cur.fetchone()
    if not profile:
        cur.close(); conn.close()
        return jsonify({'error': 'Profile not found'}), 404

    full_name, email, phone, role, subrole, position = profile
    full_name_lower = (full_name or "").strip().lower()

    cur.execute("""
        SELECT ROUND(AVG(aa.score_obtained), 2) AS average_gpa
        FROM assessmentanswers aa
        JOIN assessments a ON aa.assessment_id = a.id
        JOIN profiles p ON a.assessee_id = p.id
        WHERE LOWER(p.full_name) = %s
    """, (full_name_lower,))
    gpa_result = cur.fetchone()
    average_gpa = gpa_result[0] if gpa_result and gpa_result[0] is not None else 0

    cur.close(); conn.close()
    return jsonify({
        'full_name': full_name, 'email': email, 'phone': phone,
        'role': role, 'subrole': subrole, 'position': position,
        'average_gpa': average_gpa
    }), 200

# ----------------------------------------
# ----------------------------------------
# REPORTS: TEAM OVERVIEW  (used by UI)
## ----------------------------------------
# REPORTS: TEAM OVERVIEW  (used by UI)
# ----------------------------------------
@app.route('/reports/team_overview', methods=['POST'])
@jwt_required()
def reports_team_overview():
    """
    Overview report using JWT role/hierarchy rules.

    Admin:
      - Sees all completed assessments.
      - Can optionally filter overview by role_scope: ALL, SFP, CC, CE.

    Channel Manager:
      - Sees same department/role except assessed Channel Managers.

    National Supervisor:
      - Sees own Supervisors + Sales Experts/field profiles.
      - Does not see National Supervisors or Channel Managers.

    Supervisor:
      - Sees own Sales Experts only.
    """
    body = request.get_json() or {}
    dfrom, dto = _parse_range(body, default_days=30)

    user = current_user_claims()
    position = user["position"]
    user_role = (user["role"] or "").strip().upper()

    # New: admin overview scope from Flutter
    role_scope = (body.get("role_scope") or "ALL").strip().upper()

    print("📊 TEAM OVERVIEW BODY:", body)
    print("📊 DATE FROM:", dfrom)
    print("📊 DATE TO:", dto)
    print("📊 USER:", user)
    print("📊 ROLE SCOPE:", role_scope)

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        where_clause = "a.completed_at BETWEEN %s AND %s"
        params = [dfrom, dto]

        if is_admin_user():
            print("📊 SCOPE: ADMIN")

            # Admin can choose ALL / SFP / CC / CE in the overview screen
            if role_scope in ("SFP", "CC", "CE"):
                where_clause += " AND UPPER(p.role) = %s"
                params.append(role_scope)
                print(f"📊 ADMIN FILTERED BY ROLE: {role_scope}")
            else:
                print("📊 ADMIN - all completed assessments")

        else:
            current_profile_id = get_current_profile_id(cur)

            if not current_profile_id:
                return jsonify({
                    "status": "error",
                    "message": "Current user profile not found"
                }), 403

            print("📊 CURRENT PROFILE ID:", current_profile_id)

            if position == "channel manager":
                where_clause += """
                    AND UPPER(p.role) = %s
                    AND LOWER(p.position) <> 'channel manager'
                """
                params.append(user_role)
                print("📊 SCOPE: CHANNEL MANAGER")

            elif position == "national supervisor":
                where_clause += """
                    AND p.national_supervisor_id = %s
                    AND LOWER(p.position) NOT IN ('national supervisor', 'channel manager')
                """
                params.append(current_profile_id)
                print("📊 SCOPE: NATIONAL SUPERVISOR")

            elif position == "supervisor":
                where_clause += """
                    AND p.supervisor_id = %s
                    AND LOWER(p.position) = 'sales expert'
                """
                params.append(current_profile_id)
                print("📊 SCOPE: SUPERVISOR")

            else:
                where_clause += " AND 1=0"
                print("📊 SCOPE: UNKNOWN / BLOCKED")

        print("📊 WHERE CLAUSE:", where_clause)
        print("📊 PARAMS:", params)

        # ---------------- TOTALS ----------------
        cur.execute(f"""
            SELECT
                COUNT(*) AS total_assessments,
                COALESCE(ROUND(AVG(a.final_score)::numeric, 2), 0) AS avg_final_on3
            FROM assessments a
            JOIN profiles p ON p.id = a.assessee_id
            WHERE {where_clause}
        """, tuple(params))

        total_assessments, avg_final_on3 = cur.fetchone()

        print("📊 TOTAL ASSESSMENTS RETURNED:", total_assessments)
        print("📊 AVG SCORE RETURNED:", avg_final_on3)

        # ---------------- BY ROLE ----------------
        cur.execute(f"""
            SELECT
                p.role,
                COUNT(*) AS cnt,
                COALESCE(ROUND(AVG(a.final_score)::numeric, 2), 0) AS avg_on3
            FROM assessments a
            JOIN profiles p ON p.id = a.assessee_id
            WHERE {where_clause}
            GROUP BY p.role
            ORDER BY cnt DESC
        """, tuple(params))

        by_role = [
            {
                "role": r,
                "count": int(c),
                "avg_on3": float(s)
            }
            for (r, c, s) in cur.fetchall()
        ]

        # ---------------- BY SUBROLE / SEGMENT ----------------
        cur.execute(f"""
            SELECT
                COALESCE(NULLIF(TRIM(p.subrole), ''), 'Unassigned') AS segment,
                COUNT(*) AS cnt,
                COALESCE(ROUND(AVG(a.final_score)::numeric, 2), 0) AS avg_on3
            FROM assessments a
            JOIN profiles p ON p.id = a.assessee_id
            WHERE {where_clause}
            GROUP BY COALESCE(NULLIF(TRIM(p.subrole), ''), 'Unassigned')
            ORDER BY cnt DESC
        """, tuple(params))

        by_secondary = [
            {
                "label": "subrole",
                "name": n,
                "count": int(c),
                "avg_on3": float(s)
            }
            for (n, c, s) in cur.fetchall()
        ]

        # ---------------- TREND PER DAY ----------------
        cur.execute(f"""
            SELECT
                DATE(a.completed_at) AS d,
                COALESCE(ROUND(AVG(a.final_score)::numeric, 2), 0) AS avg_on3,
                COUNT(*) AS cnt
            FROM assessments a
            JOIN profiles p ON p.id = a.assessee_id
            WHERE {where_clause}
            GROUP BY DATE(a.completed_at)
            ORDER BY DATE(a.completed_at)
        """, tuple(params))

        trend = [
            {
                "date": d.strftime("%Y-%m-%d"),
                "avg_on3": float(s),
                "count": int(c)
            }
            for (d, s, c) in cur.fetchall()
        ]

        print("📊 BY ROLE:", by_role)
        print("📊 BY SECONDARY:", by_secondary)
        print("📊 TREND POINTS:", trend)

        return jsonify({
            "status": "success",
            "window": {
                "from": dfrom.isoformat(),
                "to": dto.isoformat()
            },
            "scope": {
                "role_scope": role_scope if is_admin_user() else user_role,
                "position": position,
                "user_role": user_role
            },
            "totals": {
                "assessments": int(total_assessments or 0),
                "avg_on3": float(avg_final_on3 or 0)
            },
            "by_role": by_role,
            "by_secondary": by_secondary,
            "trend": trend,
            "debug": {
                "position": position,
                "user_role": user_role,
                "role_scope": role_scope,
                "where_clause": where_clause,
                "params": [str(p) for p in params]
            }
        }), 200

    except Exception as e:
        print("❌ /reports/team_overview:", e)
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

    finally:
        cur.close()
        conn.close()

# ----------------------------------------
# REPORTS: INDIVIDUAL OVERVIEW  (used by UI)
# ----------------------------------------
@app.route('/reports/individual_overview', methods=['POST'])
@jwt_required()
def reports_individual_overview():
    """
    Body: { "member_id": <profiles.id>, "date_from": "...", "date_to": "..." }
    Overall (on 3) = question-weighted average from ACO:
        sum( avg_score * answered_q ) / sum(answered_q)
    """
    body = request.get_json() or {}
    member_id = body.get('member_id')
    if not member_id:
        return jsonify({"status":"error","message":"member_id required"}), 400
    dfrom, dto = _parse_range(body, default_days=365)

    conn = get_db_connection(); cur = conn.cursor()

        # ✅ SECURITY: Check if user can access this employee's report
    if not can_access_profile(cur, int(member_id)):
        cur.close()
        conn.close()
        return jsonify({
            "status": "error",
            "message": "Forbidden: you cannot access this employee report"
        }), 403
    

    try:
        # Header
        cur.execute("SELECT id, full_name, role, subrole, position FROM profiles WHERE id = %s", (member_id,))
        hdr = cur.fetchone()
        if not hdr: return jsonify({"status":"error","message":"member not found"}), 404
        pid, name, role, subrole, position = hdr

        # Overall weighted on 3
        cur.execute("""
            SELECT
              COALESCE(ROUND(
                SUM(aco.avg_score * aco.answered_questions)
                / NULLIF(SUM(aco.answered_questions),0)
              ::numeric, 2), 0) AS overall_on3,
              COALESCE(SUM(aco.answered_questions),0) AS answered_q_total,
              COUNT(DISTINCT aco.assessment_id) AS assessments_in_window
            FROM assessment_category_outcome aco
            JOIN assessments a ON a.id = aco.assessment_id
            WHERE a.assessee_id = %s
              AND a.completed_at BETWEEN %s AND %s
        """, (member_id, dfrom, dto))
        overall_on3, answered_q_total, assess_cnt = cur.fetchone()

        # Category details
        cur.execute("""
            SELECT aco.category_title,
                   SUM(aco.total_questions)       AS total_q,
                   SUM(aco.answered_questions)    AS answered_q,
                   SUM(aco.right_count)           AS right_q,
                   SUM(aco.partial_count)         AS partial_q,
                   SUM(aco.wrong_count)           AS wrong_q,
                   COALESCE(ROUND(
                     SUM(aco.avg_score * aco.answered_questions)
                     / NULLIF(SUM(aco.answered_questions),0)
                   ::numeric, 2), 0)              AS avg_on3
            FROM assessment_category_outcome aco
            JOIN assessments a ON a.id = aco.assessment_id
            WHERE a.assessee_id = %s
              AND a.completed_at BETWEEN %s AND %s
            GROUP BY aco.category_title
            ORDER BY aco.category_title
        """, (member_id, dfrom, dto))
        categories = [{
            "category": c, "total_q": int(tq or 0), "answered_q": int(aq or 0),
            "right": int(r or 0), "partial": int(p or 0), "wrong": int(w or 0),
            "avg_on3": float(avg or 0)
        } for (c,tq,aq,r,p,w,avg) in cur.fetchall()]

        # Timeline (assessments)
        cur.execute("""
            SELECT a.id, a.completed_at, a.final_score
            FROM assessments a
            WHERE a.assessee_id = %s
              AND a.completed_at BETWEEN %s AND %s
            ORDER BY a.completed_at
        """, (member_id, dfrom, dto))
        timeline = [{
            "assessment_id": i,
            "date": dt.strftime("%Y-%m-%d"),
            "final_on3": float(s or 0)
        } for (i,dt,s) in cur.fetchall()]

        return jsonify({
            "status":"success",
            "member":{"id": pid, "name": name, "role": role, "subrole": subrole, "position": position},
            "window":{"from": dfrom.isoformat(), "to": dto.isoformat()},
            "overall":{"final_on3": float(overall_on3 or 0), "answered_q_total": int(answered_q_total or 0),
                       "assessments": int(assess_cnt or 0)},
            "categories": categories,
            "timeline": timeline
        }), 200
    except Exception as e:
        print("❌ /reports/individual_overview:", e)
        return jsonify({"status":"error","message":str(e)}), 500
    finally:
        cur.close(); conn.close()

# ----------------------------------------
# REPORTS: INDIVIDUAL PER-CATEGORY SERIES  (used by UI)
# ----------------------------------------
@app.route('/reports/individual_category_series', methods=['POST'])
@jwt_required()
def reports_individual_category_series():
    """
    Body: { "member_id": <profiles.id>, "category_title": "..." }
    Returns avg_on3 by attempt order for this category from ACO.
    """
    body = request.get_json() or {}
    member_id = body.get('member_id')
    category  = (body.get('category_title') or '').strip()
    if not member_id or not category:
        return jsonify({"status":"error","message":"member_id and category_title required"}), 400

    conn = get_db_connection(); cur = conn.cursor()

        # ✅ SECURITY: Check if user can access this employee's report
    if not can_access_profile(cur, int(member_id)):
        cur.close()
        conn.close()
        return jsonify({
            "status": "error",
            "message": "Forbidden: you cannot access this employee report"
        }), 403
    

    try:
        cur.execute("""
            SELECT attempt_seq,
                   COALESCE(ROUND(
                     SUM(avg_score * answered_questions)
                     / NULLIF(SUM(answered_questions),0)
                   ::numeric, 2), 0) AS avg_on3
            FROM assessment_category_outcome
            WHERE assessee_id = %s
              AND category_title = %s
            GROUP BY attempt_seq
            ORDER BY attempt_seq
        """, (member_id, category))
        series = [{"attempt": int(a), "avg_on3": float(s or 0)} for (a,s) in cur.fetchall()]
        return jsonify({"status":"success","category": category, "series": series}), 200
    except Exception as e:
        print("❌ /reports/individual_category_series:", e)
        return jsonify({"status":"error","message":str(e)}), 500
    finally:
        cur.close(); conn.close()

# ----------------------- GET ONE PROFILE (with names) -----------------------
from flask import jsonify, request
import traceback

@app.route('/profile_get', methods=['GET'])
@jwt_required()
def profile_get():
    """
    GET /profile_get?id=160
    Returns a single profile. Never references channel_manager_id.
    Joins supervisor/national supervisor names only if *_id columns exist.
    """
    pid_raw = (request.args.get('id') or '').strip()
    try:
        pid = int(pid_raw)
        if pid <= 0:
            raise ValueError()
    except Exception:
        return jsonify({'error': 'invalid id'}), 400

    conn = get_db_connection(); cur = conn.cursor()

    if not can_access_profile(cur, pid):
        cur.close()
        conn.close()
        return jsonify({'error': 'Forbidden: you cannot access this profile'}), 403
    

    try:
        # discover what columns exist (current schema)
        cur.execute("""
            SELECT LOWER(column_name)
            FROM information_schema.columns
            WHERE table_schema = current_schema()
              AND table_name = 'profiles'
        """)
        cols = {r[0] for r in cur.fetchall()}

        select_exprs = []
        key_order = []

        # base columns (include only if present)
        for c in ['id', 'full_name', 'role', 'subrole', 'position']:
            if c in cols:
                select_exprs.append(f"p.{c}")
                key_order.append(c)

        # optional text
        if 'phone' in cols:
            select_exprs.append("COALESCE(p.phone, '') AS phone"); key_order.append('phone')
        if 'email' in cols:
            select_exprs.append("COALESCE(p.email, '') AS email"); key_order.append('email')
        if 'zone' in cols:
            select_exprs.append("COALESCE(p.zone, '') AS zone"); key_order.append('zone')

        # date as string if present
        if 'date_joined' in cols:
            select_exprs.append("to_char(p.date_joined, 'YYYY-MM-DD') AS date_joined")
            key_order.append('date_joined')

        # supervisor / national supervisor
        joins = []
        if 'supervisor_id' in cols:
            select_exprs.append("p.supervisor_id"); key_order.append('supervisor_id')
            select_exprs.append("COALESCE(sup.full_name, '') AS supervisor_name"); key_order.append('supervisor_name')
            joins.append("LEFT JOIN profiles sup ON sup.id = p.supervisor_id")

        if 'national_supervisor_id' in cols:
            select_exprs.append("p.national_supervisor_id"); key_order.append('national_supervisor_id')
            select_exprs.append("COALESCE(ns.full_name, '') AS national_supervisor_name"); key_order.append('national_supervisor_name')
            joins.append("LEFT JOIN profiles ns ON ns.id = p.national_supervisor_id")

        if not select_exprs:
            return jsonify({'error': 'profiles table missing expected columns'}), 500

        select_sql = ",\n              ".join(select_exprs)
        joins_sql = "\n            ".join(joins)

        sql = f"""
            SELECT
              {select_sql}
            FROM profiles p
            {joins_sql}
            WHERE p.id = %s
            LIMIT 1
        """
        cur.execute(sql, (pid,))
        row = cur.fetchone()
        if not row:
            return jsonify({'error': 'not found'}), 404

        profile = {k: row[i] for i, k in enumerate(key_order)}

        # normalize empties
        for k in ['full_name','role','subrole','position','phone','email','zone',
                  'supervisor_name','national_supervisor_name']:
            if k in profile and profile[k] is None:
                profile[k] = ''
        if 'date_joined' in profile and profile['date_joined'] is None:
            profile['date_joined'] = ''

        return jsonify({'profile': profile}), 200

    except Exception as e:
        print("ERROR /profile_get:", e)
        traceback.print_exc()
        return jsonify({'error': 'internal server error', 'detail': str(e)}), 500
    finally:
        cur.close(); conn.close()


# ----------------------- UPDATE PROFILE (diff-based) -----------------------
@app.route('/profile_update', methods=['PUT'])
@jwt_required()
def profile_update():
    """
    PUT /profile_update
    Body (diff-only):
      {
        "id": 123,
        "full_name": "...",
        "phone": "...",
        "email": "...",
        "role": "SFP|CE|CC",
        "subrole": "...",
        "position": "channel manager|national supervisor|supervisor|sales expert",
        "zone": "...",
        "date_joined": "YYYY-MM-DD" | "",
        "supervisor_name": "Chouaib ..." | null | "",
        "national_supervisor_name": "Zouhair ..." | null | ""
      }
    Notes:
      - Never touches channel_manager_id.
      - Resolves *_name to *_id only if the *_id column exists in 'profiles'.
      - Only updates columns that exist in your current schema.
    """
    data = request.get_json(silent=True) or {}
    pid = data.get('id')
    if not pid or not isinstance(pid, int) or pid <= 0:
        return jsonify({'error': 'valid id is required'}), 400

    allowed_roles = {'SFP','CE','CC'}
    allowed_positions = {'channel manager','national supervisor','supervisor','sales expert'}

    conn = get_db_connection(); cur = conn.cursor()

    if not can_access_profile(cur, pid):
        cur.close()
        conn.close()
        return jsonify({'error': 'Forbidden: you cannot update this profile'}), 403
    

    try:
        # discover columns present now
        cur.execute("""
            SELECT LOWER(column_name)
            FROM information_schema.columns
            WHERE table_schema = current_schema()
              AND table_name = 'profiles'
        """)
        cols = {r[0] for r in cur.fetchall()}

        # pull current row (for role scoping)
        if 'role' in cols:
            cur.execute("SELECT role FROM profiles WHERE id = %s", (pid,))
            row = cur.fetchone()
            if not row:
                return jsonify({'error': 'not found'}), 404
            current_role = (row[0] or '').upper()
        else:
            current_role = ''

        # figure effective role (new if provided/valid else current)
        incoming_role = (data.get('role') or '').upper()
        effective_role = incoming_role if incoming_role else current_role
        if incoming_role and incoming_role not in allowed_roles:
            return jsonify({'error': f'invalid role {incoming_role}'}), 400

        # helper: resolve profile id by name (scoped by role + position if given)
        def resolve_profile_id_by_name(name, role_hint=None, position_hint=None):
            if not name:
                return None
            q = "SELECT id FROM profiles WHERE LOWER(full_name) = LOWER(%s)"
            params = [name]
            if role_hint and 'role' in cols:
                q += " AND role = %s"
                params.append(role_hint)
            if position_hint and 'position' in cols:
                q += " AND LOWER(position) = LOWER(%s)"
                params.append(position_hint)
            q += " LIMIT 1"
            cur.execute(q, tuple(params))
            r = cur.fetchone()
            return r[0] if r else None

        updates = []
        params  = []

        # text-like fields (update only if column exists and key provided)
        for col in ('full_name','phone','email','subrole','zone'):
            if (col in cols) and (col in data):
                updates.append(f"{col} = %s")
                params.append((data.get(col) or '').strip())

        # date_joined as string/null (let Postgres cast or set NULL)
        if ('date_joined' in cols) and ('date_joined' in data):
            val = (data.get('date_joined') or '').strip()
            updates.append("date_joined = %s")
            params.append(val if val else None)

        # role
        if ('role' in cols) and ('role' in data):
            updates.append("role = %s")
            params.append(incoming_role if incoming_role else None)

        # position
        if ('position' in cols) and ('position' in data):
            pos_val = (data.get('position') or '').lower()
            if pos_val and pos_val not in allowed_positions:
                return jsonify({'error': f'invalid position {pos_val}'}), 400
            updates.append("position = %s")
            params.append(pos_val if pos_val else None)

        # supervisor_name -> supervisor_id (if column exists)
        if ('supervisor_id' in cols) and ('supervisor_name' in data):
            sup_name = (data.get('supervisor_name') or '').strip()
            if not sup_name:
                updates.append("supervisor_id = NULL")
            else:
                sup_id = resolve_profile_id_by_name(
                    sup_name,
                    role_hint=effective_role if effective_role in allowed_roles else None,
                    position_hint='supervisor'
                )
                if not sup_id:
                    return jsonify({'error': 'supervisor_name not found', 'value': sup_name}), 400
                updates.append("supervisor_id = %s")
                params.append(sup_id)

        # national_supervisor_name -> national_supervisor_id (if column exists)
        if ('national_supervisor_id' in cols) and ('national_supervisor_name' in data):
            ns_name = (data.get('national_supervisor_name') or '').strip()
            if not ns_name:
                updates.append("national_supervisor_id = NULL")
            else:
                ns_id = resolve_profile_id_by_name(
                    ns_name,
                    role_hint=effective_role if effective_role in allowed_roles else None,
                    position_hint='national supervisor'
                )
                if not ns_id:
                    return jsonify({'error': 'national_supervisor_name not found', 'value': ns_name}), 400
                updates.append("national_supervisor_id = %s")
                params.append(ns_id)

        if not updates:
            return jsonify({'updated': False}), 200

        set_sql = ", ".join(updates)
        params.append(pid)
        cur.execute(f"UPDATE profiles SET {set_sql} WHERE id = %s", tuple(params))
        conn.commit()

        # return fresh row via the same safe reader
        return profile_get()

    except Exception as e:
        conn.rollback()
        print("ERROR /profile_update:", e)
        traceback.print_exc()
        return jsonify({'error': 'internal server error', 'detail': str(e)}), 500
    finally:
        cur.close(); conn.close()



# ----------------------------------------
# MAIN
# ----------------------------------------
if __name__ == '__main__':
    app.run(debug=True)