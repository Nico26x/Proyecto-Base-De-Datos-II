import random
from datetime import datetime, timedelta
from faker import Faker
from config import get_connection

fake = Faker('es_CO')

def poblar_base_datos():
    conn = get_connection()
    cursor = conn.cursor()
    print("Iniciando la carga masiva de datos en Oracle XE...")

    # 1. MUNICIPIOS (12 del Quindío)
    municipios = [
        'Armenia', 'Salento', 'Filandia', 'Montenegro', 'Quimbaya',
        'Calarcá', 'Circasia', 'La Tebaida', 'Pijao', 'Buenavista', 'Córdoba', 'Génova'
    ]
    for mun in municipios:
        cursor.execute("INSERT INTO municipio (nombre) VALUES (:1)", [mun])
    print("✓ 12 Municipios insertados.")

    # 2. TIPOS DE ALOJAMIENTO
    tipos_alojamiento = [
        ('Finca Cafetera', 'Alojamiento rural rodeado de cultivos de café'),
        ('Hotel Céntrico', 'Hotel urbano con acceso a comercio y transporte'),
        ('Glamping', 'Experiencia de lujo en medio de la naturaleza'),
        ('Hostal', 'Hospedaje económico con áreas compartidas'),
        ('Cabaña', 'Cabaña privada en entorno montañoso')
    ]
    for tipo, desc in tipos_alojamiento:
        cursor.execute("INSERT INTO tipo_alojamiento (nombre, descripcion) VALUES (:1, :2)", [tipo, desc])
    print("✓ 5 Tipos de Alojamiento insertados.")

    # 3. ALOJAMIENTOS (60 Alojamientos repartidos en los 12 municipios)
    alojamientos_data = []
    prefijos = ['Finca La', 'Hotel El', 'Glamping Alto', 'Hostal', 'Cabañas Las']
    for i in range(1, 61):
        nombre = f"{random.choice(prefijos)} {fake.first_name()} #{i}"
        direccion = f"Km {random.randint(1, 15)} Vía {fake.street_name()}"
        telefono = f"3{random.randint(100000000, 999999999)}"
        correo = f"contacto_alojamiento_{i}@turismouq.com"
        id_mun = random.randint(1, 12)
        id_tipo = random.randint(1, 5)
        alojamientos_data.append((nombre, direccion, telefono, correo, id_mun, id_tipo))
    
    cursor.executemany("""
        INSERT INTO alojamiento (nombre, direccion, telefono, correo, id_municipio, id_tipo_alojamiento)
        VALUES (:1, :2, :3, :4, :5, :6)
    """, alojamientos_data)
    print("✓ 60 Alojamientos insertados.")

    # 4. HABITACIONES (400 Habitaciones distribuidas)
    habitaciones_data = []
    tipos_hab = ['ESTANDAR', 'SUITE', 'FAMILIAR', 'GLAMPING_DELUXE', 'CABANA_RUSTICA']
    for i in range(1, 401):
        num_hab = f"H-{100 + (i % 50)}"
        tipo = random.choice(tipos_hab)
        capacidad = random.randint(2, 6)
        desc = f"Habitación {tipo} equipada con vista al paisaje cafetero"
        id_aloj = random.randint(1, 60)
        habitaciones_data.append((num_hab, tipo, capacidad, desc, id_aloj))

    cursor.executemany("""
        INSERT INTO habitacion (numero_habitacion, tipo, capacidad, descripcion, id_alojamiento)
        VALUES (:1, :2, :3, :4, :5)
    """, habitaciones_data)
    print("✓ 400 Habitaciones insertadas.")

    # 5. TEMPORADAS Y TARIFAS
    temporadas = [
        ('Semana Santa 2024', datetime(2024, 3, 24), datetime(2024, 3, 31), 'ALTA'),
        ('Mitad de Año 2024', datetime(2024, 6, 15), datetime(2024, 7, 20), 'ALTA'),
        ('Diciembre-Enero 2024', datetime(2024, 12, 1), datetime(2025, 1, 20), 'ALTA'),
        ('Temporada Baja 2024', datetime(2024, 1, 1), datetime(2024, 12, 31), 'BAJA'),
        ('Temporada Baja 2025', datetime(2025, 1, 1), datetime(2025, 12, 31), 'BAJA'),
        ('Temporada Baja 2026', datetime(2026, 1, 1), datetime(2026, 12, 31), 'BAJA')
    ]
    for nom, f_in, f_out, tipo_temp in temporadas:
        cursor.execute("""
            INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, tipo_temporada)
            VALUES (:1, :2, :3, :4)
        """, [nom, f_in, f_out, tipo_temp])
    
    # Tarifas por habitación y temporada
    tarifas_data = []
    for h_id in range(1, 401):
        for temp_id in range(1, 7):
            precio = round(random.uniform(120000, 450000), 2)
            tarifas_data.append((h_id, temp_id, precio))
    
    cursor.executemany("""
        INSERT INTO tarifa (id_habitacion, id_temporada, precio_noche)
        VALUES (:1, :2, :3)
    """, tarifas_data)
    print("✓ Temporadas y Tarifas insertadas.")

    # 6. CLIENTES (3.000 Clientes)
    clientes_data = []
    tipos_doc = ['CC', 'CE', 'PASAPORTE']
    for i in range(1, 3001):
        doc = f"{random.randint(10000000, 1099999999)}"
        tdoc = random.choice(tipos_doc)
        nom = fake.first_name()
        ape = fake.last_name()
        correo = f"cliente_{i}_{doc}@mail.com"
        tel = f"3{random.randint(100000000, 999999999)}"
        clientes_data.append((doc, tdoc, nom, ape, correo, tel))

    cursor.executemany("""
        INSERT INTO cliente (num_documento, tipo_documento, nombres, apellidos, correo, telefono)
        VALUES (:1, :2, :3, :4, :5, :6)
    """, clientes_data)
    print("✓ 3.000 Clientes insertados.")

    # 7. SERVICIOS
    servicios = [
        ('Tour del Café', 'Recorrido guiado por cafetales con catación', 45000),
        ('Paseo a Caballo', 'Cabalgata por senderos ecológicos', 60000),
        ('Cena Romántica', 'Cena gourmet de 3 tiempos con vino', 120000),
        ('Desayuno Campesino', 'Desayuno típico con arepa de choclo', 20000),
        ('Spa y Masaje', 'Sesión de relajación e hidroterapia', 90000)
    ]
    for s_nom, s_desc, s_precio in servicios:
        cursor.execute("""
            INSERT INTO servicio (nombre, descripcion, precio_base)
            VALUES (:1, :2, :3)
        """, [s_nom, s_desc, s_precio])
    print("✓ Servicios insertados.")

    # 8. RESERVAS (25.000) Y SERVICIOS ASOCIADOS (40.000)
    print("Generando 25.000 reservas (esto tomará unos segundos)...")
    
    reservas_data = []
    reserva_hab_data = []
    reserva_serv_data = []
    estados = ['CONFIRMADA', 'FINALIZADA', 'CANCELADA', 'PENDIENTE']
    
    start_date = datetime(2024, 1, 1)
    
    for r_id in range(1, 25001):
        f_res = start_date + timedelta(days=random.randint(0, 900))
        f_in = f_res + timedelta(days=random.randint(1, 15))
        f_out = f_in + timedelta(days=random.randint(1, 7))
        estado = random.choice(estados)
        id_cli = random.randint(1, 3000)
        
        # Habitación asociada
        id_hab = random.randint(1, 400)
        noches = (f_out - f_in).days
        precio_hab = round(noches * random.uniform(130000, 350000), 2)
        total_reserva = precio_hab
        
        reservas_data.append((f_res, f_in, f_out, estado, total_reserva, id_cli))
        reserva_hab_data.append((r_id, id_hab, precio_hab))
    
    # Inserción en lote de Reservas
    cursor.executemany("""
        INSERT INTO reserva (fecha_reserva, fecha_checkin, fecha_checkout, estado, total, id_cliente)
        VALUES (:1, :2, :3, :4, :5, :6)
    """, reservas_data)
    
    cursor.executemany("""
        INSERT INTO reserva_habitacion (id_reserva, id_habitacion, precio_noches_total)
        VALUES (:1, :2, :3)
    """, reserva_hab_data)
    
    # Generar 40.000 líneas de servicios
    for s_id in range(1, 40001):
        id_res = random.randint(1, 25000)
        id_serv = random.randint(1, 5)
        cant = random.randint(1, 4)
        p_unit = [45000, 60000, 120000, 20000, 90000][id_serv - 1]
        subtot = cant * p_unit
        reserva_serv_data.append((id_res, id_serv, cant, p_unit, subtot))

    cursor.executemany("""
        INSERT INTO reserva_servicio (id_reserva, id_servicio, cantidad, precio_unitario, subtotal)
        VALUES (:1, :2, :3, :4, :5)
    """, reserva_serv_data)

    conn.commit()
    cursor.close()
    conn.close()
    print("¡CARGA MASIVA COMPLETADA CON ÉXITO EN ORACLE XE!")

if __name__ == '__main__':
    poblar_base_datos()