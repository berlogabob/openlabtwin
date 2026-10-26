"""Load IADE's Semana 8 programme (26-30 Oct 2026) into the schedule as events, or `--dry` to print them.

Usage: uv run python scripts/semana8.py [--dry]
Source: the programme PDFs (26.10 from the corrected Day1 file). Events at TechLab | GameStudio get the Tech Lab place, so
they show in the TV's day column; the rest keep their room as free text. Every row's public_note starts with "Semana 8"
(tv.py tags and highlights those). Re-running replaces the week's rows. Remove them after the week:
DELETE activities WHERE public_note LIKE 'Semana 8%'.
"""
import sys
from datetime import datetime

from db import connect, request, select
from timetable_parse import TZ

LAB = "TechLab | GameStudio"
# (day, start, end, title, room, guests)
PROGRAMME = [
    ("26", "09:00", "18:00", "AMOSTRA | Exposição dos Melhores Trabalhos", "Edifício OGC", "Vários cursos"),
    ("26", "16:00", "18:00", "First Impressions | Photo shoot", "Estúdio de Fotografia", "Mónica Lameiro / Camila Jordão"),
    ("26", "09:00", "10:00", "IADE Game Jam | Briefing", LAB, "José Graça"),
    ("26", "11:00", "13:00", "Farelo Studio", "Fábrica", "Pedro Farelo / Mónica Lameiro"),
    ("26", "16:00", "17:00", "Direção de Arte, Publicidade e Direção Criativa para Novos Designers", "Sala 09", "Rodrigo Morais"),
    ("26", "14:00", "16:00", "MixMedia | Flipbook", "Sala 104", "Samuel Rodeia"),
    ("26", "09:30", "17:30", "Seleção de Filmes dos Alunos de L-ACV", "Sala 106", "Sérgio Bordalo e Sá"),
    ("26", "09:00", "16:30", "AnimationJam 26", "Sala 103", "Hugo Passarinho"),
    ("27", "14:00", "16:00", "Workshop MixMedia | Flipbook", "Sala 105", "Samuel Rodeia"),
    ("27", "11:00", "14:00", "Workshop de Iniciação à Captação de Áudio e Vídeo", "MediaLab - Estúdio 1", "Mário Brás"),
    ("27", "10:00", "13:00", "Workshop de Figma", "Sala 020", "Samuel Rodeia"),
    ("27", "14:00", "16:30", "Workshop de Blender", "Sala 110", "Ricardo Megre"),
    ("27", "14:30", "16:30", "Workshop de Encadernação", "PrintLab", "Filipa Oliveira / João Flecha"),
    ("27", "15:00", "17:00", "Workshop on Building an Autonomous Exam Prep & Faculty Simulator with Local LLMs", "Fábrica",
     "Nuno Andrade / Eimy Blanco"),
    ("27", "14:00", "18:00", "Workshop de Paper Fashion", "PrintLab", "João Flecha / Luís Santos / Caroline Loss"),
    ("27", "14:00", "16:00", "Showcase de Jogos", LAB, "José Graça / Eulerson Rodrigues"),
    ("27", "09:30", "17:30", "Seleção de Filmes dos Alunos de L-ACV", "Sala 106", "Sérgio Bordalo e Sá"),
    ("27", "10:00", "16:30", "AnimationJam 26", "Sala 104", "Hugo Passarinho"),
    ("28", "10:30", "13:30", "Insights | 15 minutos sem filtros", "Fábrica", "Vários oradores"),
    ("28", "18:45", "21:45", "PULSE | Colloquium on Marketing, Innovation, Communication, Branding & Strategy", "Auditório 3",
     "Vários oradores"),
    ("28", "19:00", "21:00", "DOVE x IADE | Autoestima, Imagem Corporal e Participação Feminina no Desporto", "Fábrica", "Maria Cadarso"),
    ("28", "21:00", "22:00", "Gerir o Design para os Resultados", "Sala 126", "Liliana Moreira / Raquel Lima"),
    ("28", "14:00", "16:00", "Workshop MixMedia | Flipbook", "Sala 110", "Samuel Rodeia"),
    ("28", "11:00", "12:30", "Com Sentido(s) | Workshop de Experiências Sensoriais", "Sala 06", "Inês Pires / Hande Ayanoglu / Hugo Simão"),
    ("28", "14:30", "16:30", "Workshop de Encadernação", "PrintLab", "Filipa Oliveira / João Flecha / Juliana Duque"),
    ("28", "14:30", "15:30", "Workshop sobre Georeferenciação", "Sala 07", "José Travanca Lopes"),
    ("28", "15:00", "18:00", "Oficina de Cartografia | De Cá para Lá", "Sala 134", "Juliana Duque / Pedro Sancho"),
    ("28", "14:00", "16:00", "Showcase de Jogos", LAB, "José Graça / Eulerson Rodrigues"),
    ("28", "09:30", "17:30", "Seleção de Filmes dos Alunos de L-ACV", "Sala 107", "Sérgio Bordalo e Sá"),
    ("28", "15:30", "17:30", "Dia da Animação | CINANIMA", "Auditório 2", "Pedro Mota Teixeira / Filipe Figueiredo"),
    ("28", "19:30", "21:30", "Dia da Animação | CASA DA ANIMAÇÃO", "Auditório 2", "Pedro Mota Teixeira / Filipe Figueiredo"),
    ("28", "10:00", "16:30", "AnimationJam 26", "Sala 117", "Hugo Passarinho"),
    ("29", "16:00", "18:00", "IADE Game Jam | Resultados", LAB, "José Graça"),
    ("29", "11:00", "13:00", "Apresentação do Gabinete de Empregabilidade e dos seus Serviços", "Sala 03", "Departamento de Empregabilidade"),
    ("29", "19:00", "20:00", "A la Will", "Online (link no QR code)", "Marta Pires Gouveia / Paulo Gouveia / Susana Cardal"),
    ("29", "11:00", "13:00", "IxD Talks | From 2D to 3D: Testing Ideas (Figma)", "Sala 109", "Bruno Figueiredo / Inês Pires"),
    ("29", "11:00", "13:00", "Arquitetura, Urbanismo, Design de Interiores e Sustentabilidade", "Sala 125",
     "Saraiva + Associados (S+A) / Mónica Lameiro"),
    ("29", "14:00", "18:00", "Workshop MixMedia | Flipbook", "Sala 105", "Samuel Rodeia"),
    ("29", "14:30", "16:30", "Workshop de Encadernação", "PrintLab", "Filipa Oliveira / João Flecha"),
    ("29", "15:00", "17:00", "Workshop de Iniciação à Captação de Áudio e Vídeo", "MediaLab - Estúdio 1", "Mário Brás"),
    ("29", "09:30", "17:30", "Seleção de Filmes dos Alunos de L-ACV", "Sala 106", "Sérgio Bordalo e Sá"),
    ("29", "10:00", "16:30", "AnimationJam 26", "Sala 104", "Hugo Passarinho"),
    ("30", "08:30", "11:30", "Processos de Impressão | Papéis, Materiais, Catálogo", "Sala 06", "João Costa"),
    ("30", "11:00", "13:00", "Como Desenvolver a Empregabilidade ao Longo do seu Percurso Académico", "Auditório 3",
     "Departamento de Empregabilidade"),
    ("30", "12:00", "17:00", "Workshop de Pinhole", "Sala 105", "Pedro Gil"),
    ("30", "09:30", "17:30", "Seleção de filmes dos alunos de L-ACV", "Sala 106", "Sérgio Bordalo e Sá"),
    ("30", "10:00", "17:00", "Halloween", LAB, "Pamela Teubig"),
    ("30", "09:00", "16:30", "AnimationJam 26", "Sala 104", "Hugo Passarinho"),
    ("30", "10:00", "12:00", "IA Improvável | Workshop de Criação de Imagens", "Fábrica", "Catarina Antunes / Mónica Lameiro"),
]


def rows(lab_id):
    def at(day, hhmm):
        return datetime.fromisoformat(f"2026-10-{day}T{hhmm}").replace(tzinfo=TZ).isoformat()
    return [{"title": t, "layer": "event", "kind": "external", "status": "approved", "starts_at": at(d, a), "ends_at": at(d, b),
             "place_ids": [lab_id] if room == LAB else [], "location_text": None if room == LAB else room,
             "public_note": f"Semana 8 · {who}"} for d, a, b, t, room, who in PROGRAMME]


if __name__ == "__main__":
    db = connect()
    lab = select(db, "places", {"select": "id", "iade_name": "like.*Tech Lab*", "order": "id", "limit": "1"})[0]["id"]
    new = rows(lab)
    if "--dry" in sys.argv:
        for r in new:
            print(r["starts_at"][:16], r["ends_at"][11:16], r["title"], "|", "LAB" if r["place_ids"] else r["location_text"])
        sys.exit(f"{len(new)} rows (dry run)")
    request(db, "DELETE", "activities", {"public_note": "like.Semana 8*"}, headers={"Prefer": "return=minimal"})
    request(db, "POST", "activities", None, new, {"Prefer": "return=minimal"})
    print(f"{len(new)} events loaded")
