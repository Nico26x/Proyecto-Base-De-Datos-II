import random
from datetime import datetime, timedelta
from faker import Faker
from config import get_connection

fake = Faker('es_CO')

def poblar_base_datos():
    conn = get_connection()
    cursor = conn.cursor()
    print("Iniciando carga masiva basada en el Diagrama ER entregado...")

    # 1. MUNICIPIOS
    municipios = [
        'Armenia', 'Salento', 'Filandia', 'Montenegro', 'Quimbaya',
        'Calarcá', 'Circasia', 'La Tebaida', 'Pijao', 'Buenavista', 'Córdoba', 'Génova'
    ]
    for mun in municipios:
        cursor.execute("INSERT INTO municipio (nombre, descripcion) VALUES (:1, :2)", [mun, f"Municipio de {mun}, Quindío"])
    print("✓ 12 Municipios insertados.")

    # 2. TIPOS DE ALOJAMIENTO
    tipos = ['Finca Cafetera', 'Hotel Céntrico', 'Glamping', 'Hostal', 'Cabaña']
    for t in tipos:
        cursor.execute("INSERT INTO tipo_alojamiento (nombre) VALUES (:1)", [t])
    print("✓ 5 Tipos de Alojamiento insertados.")

    # 3. ALOJAMIENTOS (60)
    alojamientos_data = []
    prefijos = ['Finca La', 'Hotel El', 'Glamping Alto', 'Hostal', 'Cabañas Las']
    for i in range(1, 61):
        nombre = f"{random.choice(prefijos)} {fake.first_name()} #{i}"
        direccion = f"Km {random.randint(1, 15)} Vía {fake.street_name()}"
        telefono = f"3{random.randint(100000000, 999999999)}"
        id_mun = random.randint(1, 12)
        id_tipo = random.randint(1, 5)
        alojamientos_data.append((id_mun, id_tipo, nombre, direccion, telefono))
    
    cursor.executemany("""
        INSERT INTO alojamiento (id_municipio, id_tipo_alojamiento, nombre, direccion, telefono)
        VALUES (:1, :2, :3, :4, :5)
    """, alojamientos_data)
    print("✓ 60 Alojamientos insertados.")

    # 4. HABITACIONES (400)
    habitaciones_data = []
    for i in range(1, 401):
        num_hab = f"H-{100 + (i % 50)}"
        capacidad = random.randint(2, 6)
        id_aloj = random.randint(1, 60)
        habitaciones_data.append((id_aloj, num_hab, capacidad))

    cursor.executemany("""
        INSERT INTO habitacion (id_alojamiento, numero, capacidad)
        VALUES (:1, :2, :3)
    """, habitaciones_data)
    print("✓ 400 Habitaciones insertadas.")

    # 5. TEMPORADAS Y TARIFAS
    temporadas = [
        ('Semana Santa 2024', datetime(2024, 3, 24), datetime(2024, 3, 31)),
        ('Mitad de Año 2024', datetime(2024, 6, 15), datetime(2024, 7, 20)),
        ('Diciembre-Enero 2024', datetime(2024, 12, 1), datetime(2025, 1, 20)),
        ('Temporada Baja 2024', datetime(2024, 1, 1), datetime(2024, 12, 31)),
        ('Temporada Baja 2025', datetime(2025, 1, 1), datetime(2025, 12, 31)),
        ('Temporada Baja 2026', datetime(2026, 1, 1), datetime(2026, 12, 31))
    ]
    for nom, f_in, f_out in temporadas:
        cursor.execute("INSERT INTO temporada (nombre, fecha_inicio, fecha_fin) VALUES (:1, :2, :3)", [nom, f_in, f_out])
    
    tarifas_data = []
    for h_id in range(1, 401):
        for temp_id in range(1, 7):
            precio = round(random.uniform(120000, 450000), 2)
            tarifas_data.append((h_id, temp_id, precio))
    
    cursor.executemany("INSERT INTO tarifa (id_habitacion, id_temporada, valor_noche) VALUES (:1, :2, :3)", tarifas_data)
    print("✓ Temporadas y Tarifas insertadas.")

    # 6. CLIENTES (3.000)
    clientes_data = []
    tipos_doc = ['CC', 'CE', 'PASAPORTE']
    for i in range(1, 3001):
        doc = f"{random.randint(10000000, 1099999999)}"
        tdoc = random.choice(tipos_doc)
        nombre = f"{fake.first_name()} {fake.last_name()}"
        email = f"cliente_{i}_{doc}@mail.com"
        clientes_data.append((tdoc, doc, nombre, email))

    cursor.executemany("""
        INSERT INTO cliente (tipo_identificacion, identificacion, nombre_completo, email)
        VALUES (:1, :2, :3, :4)
    """, clientes_data)
    print("✓ 3.000 Clientes insertados.")

    # 7. SERVICIOS POR ALOJAMIENTO
    servicios_data = []
    nombres_serv = ['Tour del Café', 'Paseo a Caballo', 'Cena Gourmet', 'Desayuno Típico', 'Spa']
    for aloj_id in range(1, 61):
        for s_nom in nombres_serv:
            precio = round(random.uniform(20000, 120000), 2)
            servicios_data.append((aloj_id, s_nom, precio))
            
    cursor.executemany("INSERT INTO servicio (id_alojamiento, nombre, precio_unitario) VALUES (:1, :2, :3)", servicios_data)
    print("✓ Servicios asociados a Alojamientos insertados.")

    # 8. RESERVAS (25.000) Y SERVICIOS (40.000)
    print("Generando 25.000 reservas...")
    reservas_data = []
    reserva_hab_data = []
    reserva_serv_data = []
    pagos_data = []
    estados = ['CONFIRMADA', 'FINALIZADA', 'CANCELADA', 'PENDIENTE']
    metodos = ['EFECTIVO', 'TARJETA', 'TRANSFERENCIA', 'PSE']
    
    start_date = datetime(2024, 1, 1)
    
    for r_id in range(1, 25001):
        f_creac = start_date + timedelta(days=random.randint(0, 900))
        f_in = f_creac + timedelta(days=random.randint(1, 15))
        f_out = f_in + timedelta(days=random.randint(1, 7))
        estado = random.choice(estados)
        id_cli = random.randint(1, 3000)
        
        reservas_data.append((id_cli, f_creac, estado))
        
        # Habitación reservada
        id_hab = random.randint(1, 400)
        noches = (f_out - f_in).days
        subtotal_hab = round(noches * random.uniform(130000, 350000), 2)
        reserva_hab_data.append((r_id, id_hab, f_in, f_out, subtotal_hab))
        
        # Pago asociado
        pagos_data.append((r_id, f_creac + timedelta(hours=2), subtotal_hab, random.choice(metodos)))

    cursor.executemany("INSERT INTO reserva (id_cliente, fecha_creacion, estado) VALUES (:1, :2, :3)", reservas_data)
    cursor.executemany("""
        INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado)
        VALUES (:1, :2, :3, :4, :5)
    """, reserva_hab_data)
    cursor.executemany("INSERT INTO pago (id_reserva, fecha_transaccion, monto, metodo) VALUES (:1, :2, :3, :4)", pagos_data)

    # 40.000 Líneas de servicio
    for _ in range(40001):
        id_res = random.randint(1, 25000)
        id_serv = random.randint(1, 300) # 60 alojamientos * 5 servicios
        cant = random.randint(1, 4)
        p_unit = round(random.uniform(20000, 100000), 2)
        subtot = cant * p_unit
        f_consumo = start_date + timedelta(days=random.randint(0, 900))
        reserva_serv_data.append((id_res, id_serv, cant, f_consumo, subtot))

    cursor.executemany("""
        INSERT INTO reserva_servicio (id_reserva, id_servicio, cantidad, fecha_consumo, subtotal)
        VALUES (:1, :2, :3, :4, :5)
    """, reserva_serv_data)

    conn.commit()
    cursor.close()
    conn.close()
    print("¡CARGA MASIVA COMPLETADA Y ALINEADA AL DIAGRAMA ER!")

if __name__ == '__main__':
    poblar_base_datos()