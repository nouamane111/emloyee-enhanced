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
    print("🗑️  Clearing existing assessments...")
    cur.execute("DELETE FROM assessment_category_outcome")
    cur.execute("DELETE FROM assessmentanswers")
    cur.execute("DELETE FROM assessments")
    conn.commit()
    print("✅ Cleared all assessments")

    # Get Nouhaila's profile ID
    cur.execute("SELECT id FROM profiles WHERE LOWER(full_name) LIKE '%nouhaila%elhamrity%'")
    nouhaila_row = cur.fetchone()
    if not nouhaila_row:
        print("❌ Nouhaila Elhamrity not found in profiles!")
        exit()
    
    nouhaila_id = nouhaila_row[0]
    print(f"✅ Found Nouhaila ID: {nouhaila_id}")

    # Templates to rotate through (SFP Direct retail templates)
    template_ids = [38, 37, 41, 36]  # LAU Direct, LAS Direct, SE Direct HOW, Supervisor Direct
    
    # Create 15 assessments spread from Jan to May 2025
    start_date = datetime(2025, 1, 15)
    end_date = datetime(2025, 5, 15)
    date_increment = (end_date - start_date) / 14  # 15 assessments = 14 gaps

    for i in range(15):
        template_id = template_ids[i % len(template_ids)]
        assessment_date = start_date + (date_increment * i)
        
        # Get template info
        cur.execute("SELECT name FROM assessmenttemplates WHERE id = %s", (template_id,))
        template_name = cur.fetchone()[0]
        
        print(f"\n📝 Creating assessment {i+1}/15 - {template_name} - {assessment_date.strftime('%Y-%m-%d')}")
        
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
            print(f"⚠️  No questions found for template {template_id}")
            continue
        
        # Target score for this assessment (75-95%)
        target_score_pct = random.uniform(75, 95)
        target_avg_on_3 = (target_score_pct / 100) * 3
        
        # Calculate how many Oui/Partiellement/Non to achieve target
        total_q = len(questions)
        oui_count = int(total_q * (target_score_pct / 100))
        partial_count = int(total_q * 0.15)  # ~15% partial
        non_count = total_q - oui_count - partial_count
        
        # Create assessment
        cur.execute("""
            INSERT INTO assessments (
                template_id, assessor_name, assessee_name, assessee_id,
                started_at, completed_at, final_score, comment
            )
            VALUES (%s, 'Ali Loutaty', 'nouhaila elhamrity', %s, %s, %s, NULL, '')
            RETURNING id
        """, (template_id, nouhaila_id, assessment_date, assessment_date))
        
        assessment_id = cur.fetchone()[0]
        
        # Prepare answer distribution
        answers = ['Oui'] * oui_count + ['Partiellement'] * partial_count + ['Non'] * non_count
        random.shuffle(answers)
        
        # Per-category tracking
        per_cat = {}
        score_map = {'Oui': 3.0, 'Partiellement': 2.0, 'Non': 1.0}
        final_pool = []
        
        # Insert answers
        for idx, (q_id, cat_id, cat_title) in enumerate(questions):
            answer = answers[idx] if idx < len(answers) else 'Oui'
            score = score_map[answer]
            
            cur.execute("""
                INSERT INTO assessmentanswers (
                    assessment_id, question_id, answer, comment, score_obtained, category_id
                ) VALUES (%s, %s, %s, '', %s, %s)
            """, (assessment_id, q_id, answer, score, cat_id))
            
            # Track per category
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
        """, (nouhaila_id, template_id))
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
                assessment_id, nouhaila_id, 'nouhaila elhamrity',
                template_id, template_name, attempt_seq,
                cat_id, acc['title'],
                acc['total_q'], acc['answered_q'],
                acc['right'], acc['partial'], acc['wrong'],
                avg_sc
            ))
        
        print(f"   ✅ Score: {final_score:.2f}/3 ({(final_score/3*100):.1f}%) - {oui_count} Oui, {partial_count} Partial, {non_count} Non")
    
    conn.commit()
    print("\n🎉 Successfully created 15 assessments for Nouhaila Elhamrity!")
    
except Exception as e:
    conn.rollback()
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()
finally:
    cur.close()
    conn.close()