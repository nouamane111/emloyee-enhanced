import psycopg2
from datetime import datetime, timedelta
import random

# Connect to database
conn = psycopg2.connect(
    host="localhost",
    database="ems_db",
    user="postgres",
    password="nouamane",
    port=5433
)
cur = conn.cursor()

try:
    print("🔍 Looking for Mohamed Ghouati...")
    
    # Find Mohamed Ghouati's profile ID
    cur.execute("""
        SELECT id, full_name, position, role, subrole 
        FROM profiles 
        WHERE LOWER(full_name) LIKE '%mohamed%ghouati%'
    """)
    mohamed_row = cur.fetchone()
    
    if not mohamed_row:
        print("❌ Mohamed Ghouati not found in profiles!")
        exit()
    
    mohamed_id, full_name, position, role, subrole = mohamed_row
    print(f"✅ Found: {full_name} (ID: {mohamed_id})")
    print(f"   Position: {position}")
    print(f"   Role: {role}")
    print(f"   Subrole: {subrole}")
    
    # Clear existing assessments for Mohamed
    print(f"\n🗑️  Clearing existing assessments for {full_name}...")
    cur.execute("""
        DELETE FROM assessment_category_outcome 
        WHERE assessee_id = %s
    """, (mohamed_id,))
    
    cur.execute("""
        DELETE FROM assessmentanswers 
        WHERE assessment_id IN (
            SELECT id FROM assessments WHERE assessee_id = %s
        )
    """, (mohamed_id,))
    
    cur.execute("""
        DELETE FROM assessments 
        WHERE assessee_id = %s
    """, (mohamed_id,))
    
    conn.commit()
    print("✅ Cleared existing assessments")
    
    # ✅ SIMPLIFIED FIX: Just use hardcoded templates directly
    print(f"\n🔍 Using SFP templates for Sales Expert...")
    
    # Use known SFP templates
    template_ids_to_check = [36, 37, 38, 41]
    
    # Verify these templates exist
    cur.execute("""
        SELECT id, name, role, subrole, position
        FROM assessmenttemplates
        WHERE id IN (36, 37, 38, 41)
        ORDER BY id
    """)
    templates = cur.fetchall()
    
    if not templates:
        print("❌ Default templates not found! Looking for any SFP templates...")
        cur.execute("""
            SELECT id, name, role, subrole, position
            FROM assessmenttemplates
            WHERE role = 'SFP'
            ORDER BY id
            LIMIT 4
        """)
        templates = cur.fetchall()
    
    if not templates:
        print("❌ No templates found at all!")
        print("\n📋 Available templates:")
        cur.execute("SELECT id, name, role, subrole, position FROM assessmenttemplates ORDER BY id")
        for t in cur.fetchall():
            print(f"   ID {t[0]}: {t[1]} ({t[2]} {t[3]} - {t[4]})")
        exit()
    
    print(f"✅ Found {len(templates)} templates:")
    template_ids = []
    for t in templates:
        print(f"   ID {t[0]}: {t[1]} ({t[2]} {t[3]} - {t[4]})")
        template_ids.append(t[0])
    
    # Create assessments from May 2024 to May 2025 (1 year)
    start_date = datetime(2024, 5, 20)
    end_date = datetime(2025, 5, 20)
    num_assessments = 24
    date_increment = (end_date - start_date) / (num_assessments - 1)
    
    print(f"\n📝 Creating {num_assessments} assessments from {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}")
    
    # Performance progression: 65% → 85% (improving)
    performance_start = 65.0
    performance_end = 85.0
    performance_increment = (performance_end - performance_start) / (num_assessments - 1)
    
    for i in range(num_assessments):
        assessment_date = start_date + (date_increment * i)
        
        # Calculate target score
        target_score_pct = performance_start + (performance_increment * i) + random.uniform(-3, 3)
        target_score_pct = max(60, min(95, target_score_pct))
        
        # Rotate through templates
        template_id = template_ids[i % len(template_ids)]
        
        # Get template info
        cur.execute("SELECT name FROM assessmenttemplates WHERE id = %s", (template_id,))
        template_row = cur.fetchone()
        if not template_row:
            print(f"⚠️  Template {template_id} not found, skipping...")
            continue
        template_name = template_row[0]
        
        print(f"\n📋 Assessment {i+1}/{num_assessments} - {assessment_date.strftime('%Y-%m-%d')}")
        print(f"   Template: {template_name} (ID: {template_id})")
        print(f"   Target: {target_score_pct:.1f}%")
        
        # Get all questions for this template
        cur.execute("""
            SELECT q.id, q.category_id, c.title
            FROM assessmentquestions q
            JOIN assessmentcategories c ON c.id = q.category_id
            WHERE c.template_id = %s
            ORDER BY q.id
        """, (template_id,))
        questions = cur.fetchall()
        
        if not questions:
            print(f"   ⚠️  No questions found for template {template_id}, skipping...")
            continue
        
        total_q = len(questions)
        print(f"   Questions: {total_q}")
        
        # Calculate answer distribution
        oui_count = int(total_q * (target_score_pct / 100))
        partial_count = int(total_q * 0.15)
        non_count = total_q - oui_count - partial_count
        
        if non_count < 0:
            partial_count += non_count
            non_count = 0
        
        # Create assessment
        cur.execute("""
            INSERT INTO assessments (
                template_id, assessor_name, assessee_name, assessee_id,
                started_at, completed_at, final_score, comment
            )
            VALUES (%s, 'Chouaib ATIF', %s, %s, %s, %s, NULL, '')
            RETURNING id
        """, (template_id, full_name, mohamed_id, assessment_date, assessment_date))
        
        assessment_id = cur.fetchone()[0]
        
        # Prepare answers
        answers = ['Oui'] * oui_count + ['Partiellement'] * partial_count + ['Non'] * non_count
        while len(answers) < total_q:
            answers.append('Oui')
        answers = answers[:total_q]
        random.shuffle(answers)
        
        # Per-category tracking
        per_cat = {}
        score_map = {'Oui': 3.0, 'Partiellement': 2.0, 'Non': 1.0}
        final_pool = []
        
        # Insert answers
        for idx, (q_id, cat_id, cat_title) in enumerate(questions):
            answer = answers[idx]
            score = score_map[answer]
            
            cur.execute("""
                INSERT INTO assessmentanswers (
                    assessment_id, question_id, answer, comment, score_obtained, category_id
                ) VALUES (%s, %s, %s, '', %s, %s)
            """, (assessment_id, q_id, answer, score, cat_id))
            
            if cat_id not in per_cat:
                per_cat[cat_id] = {
                    'title': cat_title,
                    'scores': [],
                    'right': 0, 'partial': 0, 'wrong': 0,
                    'total_q': 0, 'answered_q': 0
                }
            
            bucket = per_cat[cat_id]
            bucket['total_q'] += 1
            bucket['answered_q'] += 1
            bucket['scores'].append(score)
            final_pool.append(score)
            
            if answer == 'Oui': bucket['right'] += 1
            elif answer == 'Partiellement': bucket['partial'] += 1
            elif answer == 'Non': bucket['wrong'] += 1
        
        # Calculate final score
        final_score = round(sum(final_pool) / len(final_pool), 2) if final_pool else 0
        cur.execute("UPDATE assessments SET final_score = %s WHERE id = %s", (final_score, assessment_id))
        
        # Get attempt sequence
        cur.execute("""
            SELECT COALESCE(MAX(attempt_seq), 0) + 1
            FROM assessment_category_outcome
            WHERE assessee_id = %s AND template_id = %s
        """, (mohamed_id, template_id))
        attempt_seq = cur.fetchone()[0] or 1
        
        # Insert category outcomes
        for cat_id, acc in per_cat.items():
            avg_sc = round(sum(acc['scores'])/len(acc['scores']), 2) if acc['scores'] else 0
            cur.execute("""
                INSERT INTO assessment_category_outcome (
                    assessment_id, assessee_id, assessee_name,
                    template_id, template_name, attempt_seq,
                    category_id, category_title,
                    total_questions, answered_questions,
                    right_count, partial_count, wrong_count,
                    avg_score
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, (
                assessment_id, mohamed_id, full_name,
                template_id, template_name, attempt_seq,
                cat_id, acc['title'],
                acc['total_q'], acc['answered_q'],
                acc['right'], acc['partial'], acc['wrong'],
                avg_sc
            ))
        
        actual_pct = (final_score / 3) * 100
        print(f"   ✅ Score: {final_score:.2f}/3 ({actual_pct:.1f}%)")
        print(f"      {oui_count} Oui, {partial_count} Partial, {non_count} Non")
    
    conn.commit()
    print(f"\n🎉 Successfully created {num_assessments} assessments for {full_name}!")
    print(f"📊 Performance: {performance_start:.1f}% → {performance_end:.1f}% (Improving)")
    
except Exception as e:
    conn.rollback()
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()
finally:
    cur.close()
    conn.close()